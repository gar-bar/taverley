import Foundation
import Security
import Combine

struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static var current: SupabaseConfiguration? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            !urlString.isEmpty,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            !key.isEmpty
        else { return nil }

        return SupabaseConfiguration(url: url, publishableKey: key)
    }
}

struct AuthUser: Codable, Equatable {
    let id: UUID
    let email: String?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    init(accessToken: String, refreshToken: String, expiresAt: Date, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        let expiresIn = try container.decode(TimeInterval.self, forKey: .expiresIn)
        expiresAt = Date().addingTimeInterval(expiresIn)
        user = try container.decode(AuthUser.self, forKey: .user)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(max(0, expiresAt.timeIntervalSinceNow), forKey: .expiresIn)
        try container.encode(user, forKey: .user)
    }
}

enum AuthenticationError: LocalizedError {
    case notConfigured
    case invalidResponse
    case service(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Supabase is not configured for this build."
        case .invalidResponse: "The sign-in service sent an invalid response."
        case let .service(message): message
        }
    }
}

actor SupabaseAuthClient {
    private let configuration: SupabaseConfiguration
    private let session: URLSession

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        struct Request: Encodable { let email: String; let password: String }
        return try await request(path: "/auth/v1/token?grant_type=password", method: "POST", body: Request(email: email, password: password))
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        struct Request: Encodable { let refreshToken: String; enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" } }
        return try await request(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", body: Request(refreshToken: refreshToken))
    }

    private func request<Body: Encodable, Response: Decodable>(path: String, method: String, body: Body) async throws -> Response {
        guard let endpoint = URL(string: path, relativeTo: configuration.url) else { throw AuthenticationError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthenticationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseError.self, from: data).message) ?? "Unable to complete sign in."
            throw AuthenticationError.service(message: message)
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct EmptyResponse: Decodable { }
    private struct SupabaseError: Decodable { let message: String }
}

@MainActor
final class AuthenticationStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isRestoring = true
    @Published var isSkippingForNow: Bool { didSet { UserDefaults.standard.set(isSkippingForNow, forKey: "skip-authentication-for-now") } }

    private let client: SupabaseAuthClient?
    private let configuration: SupabaseConfiguration?
    private let sessionStore = SecureSessionStore()

    init(configuration: SupabaseConfiguration? = .current) {
        self.configuration = configuration
        isSkippingForNow = UserDefaults.standard.bool(forKey: "skip-authentication-for-now")
        client = configuration.map { SupabaseAuthClient(configuration: $0) }
        session = sessionStore.load()
        if let session {
            Task { await restore(session) }
        } else {
            isRestoring = false
        }
    }

    var isConfigured: Bool { client != nil }
    var dataClient: SupabaseDataClient? { configuration.map { SupabaseDataClient(configuration: $0) } }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw AuthenticationError.notConfigured }
        let newSession = try await client.signIn(email: email, password: password)
        sessionStore.save(newSession)
        session = newSession
    }

    func signOut() {
        sessionStore.clear()
        session = nil
        isSkippingForNow = false
    }

    private func restore(_ savedSession: AuthSession) async {
        defer { isRestoring = false }
        guard savedSession.expiresAt.timeIntervalSinceNow < 60 else { return }
        guard let client else {
            sessionStore.clear()
            session = nil
            return
        }
        do {
            let refreshedSession = try await client.refresh(savedSession.refreshToken)
            sessionStore.save(refreshedSession)
            session = refreshedSession
        } catch {
            sessionStore.clear()
            session = nil
        }
    }
}

private final class SecureSessionStore {
    private let service = "com.recipeapp.mealcore.auth"
    private let account = "supabase-session"

    func load() -> AuthSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let savedSession = try? JSONDecoder().decode(AuthSession.self, from: data)
        else { return nil }
        return savedSession
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
