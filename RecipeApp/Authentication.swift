import Foundation
import Security
import Combine

struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static var current: SupabaseConfiguration? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: value), !value.isEmpty,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String, !key.isEmpty else { return nil }
        return SupabaseConfiguration(url: url, publishableKey: key)
    }
}

struct AuthUser: Codable, Equatable { let id: UUID; let email: String? }

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    private enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token"; case expiresIn = "expires_in"; case user }

    init(accessToken: String, refreshToken: String, expiresAt: Date, user: AuthUser) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.user = user
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decode(String.self, forKey: .refreshToken)
        expiresAt = Date().addingTimeInterval(try values.decode(TimeInterval.self, forKey: .expiresIn))
        user = try values.decode(AuthUser.self, forKey: .user)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accessToken, forKey: .accessToken)
        try values.encode(refreshToken, forKey: .refreshToken)
        try values.encode(max(0, expiresAt.timeIntervalSinceNow), forKey: .expiresIn)
        try values.encode(user, forKey: .user)
    }
}

enum PendingAuthKind: String { case signup, recovery }

enum PasswordPolicy {
    static let minimumLength = 12
    private static let symbols = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{};'\":|<>?,./`~\\")
    static func hasMinimumLength(_ value: String) -> Bool { value.count >= minimumLength }
    static func hasNumber(_ value: String) -> Bool { value.rangeOfCharacter(from: .decimalDigits) != nil }
    static func hasSymbol(_ value: String) -> Bool { value.rangeOfCharacter(from: symbols) != nil }
    static func isValid(_ value: String) -> Bool { hasMinimumLength(value) && hasNumber(value) && hasSymbol(value) }
}

enum AuthenticationError: LocalizedError, Equatable {
    case notConfigured, invalidResponse, invalidEmail, invalidUsername, weakPassword, passwordsDoNotMatch, usernameTaken, rateLimited
    case service(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Supabase is not configured for this build."
        case .invalidResponse: "The authentication service sent an invalid response."
        case .invalidEmail: "Enter a valid email address."
        case .invalidUsername: "Use 3–30 lowercase letters, numbers, periods, or underscores."
        case .weakPassword: "Use at least 12 characters with a number and a symbol."
        case .passwordsDoNotMatch: "The passwords do not match."
        case .usernameTaken: "That username is already taken."
        case .rateLimited: "Too many attempts. Please wait a moment and try again."
        case let .service(message): message
        }
    }
}

actor SupabaseAuthClient {
    private let configuration: SupabaseConfiguration
    private let session: URLSession

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) { self.configuration = configuration; self.session = session }

    func signIn(email: String, password: String) async throws -> AuthSession {
        struct Body: Encodable { let email: String; let password: String }
        return try await request(path: "/auth/v1/token?grant_type=password", method: "POST", body: Body(email: email, password: password))
    }

    func signUp(email: String, password: String, username: String) async throws {
        struct Metadata: Encodable { let username: String }
        struct Body: Encodable { let email: String; let password: String; let data: Metadata }
        try await requestIgnoringResponse(path: "/auth/v1/signup", method: "POST", body: Body(email: email, password: password, data: Metadata(username: username)))
    }

    func verify(email: String, token: String, type: PendingAuthKind) async throws -> AuthSession {
        struct Body: Encodable { let email: String; let token: String; let type: String }
        return try await request(path: "/auth/v1/verify", method: "POST", body: Body(email: email, token: token, type: type.rawValue))
    }

    func resendSignupCode(email: String) async throws {
        struct Body: Encodable { let email: String; let type = "signup" }
        try await requestIgnoringResponse(path: "/auth/v1/resend", method: "POST", body: Body(email: email))
    }

    func requestPasswordRecovery(email: String) async throws {
        struct Body: Encodable { let email: String }
        try await requestIgnoringResponse(path: "/auth/v1/recover", method: "POST", body: Body(email: email))
    }

    func updatePassword(_ password: String, accessToken: String) async throws {
        struct Body: Encodable { let password: String }
        try await requestIgnoringResponse(path: "/auth/v1/user", method: "PUT", body: Body(password: password), accessToken: accessToken)
    }

    func refresh(_ token: String) async throws -> AuthSession {
        struct Body: Encodable { let refreshToken: String; enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" } }
        return try await request(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", body: Body(refreshToken: token))
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        struct Body: Encodable { let candidate: String }
        return try await request(path: "/rest/v1/rpc/is_username_available", method: "POST", body: Body(candidate: username))
    }

    func claimUsername(_ username: String, accessToken: String) async throws {
        struct Body: Encodable { let candidate: String }
        do { try await requestIgnoringResponse(path: "/rest/v1/rpc/claim_username", method: "POST", body: Body(candidate: username), accessToken: accessToken) }
        catch let error as AuthenticationError {
            if case let .service(message) = error, message.localizedCaseInsensitiveContains("username") || message.localizedCaseInsensitiveContains("unique") { throw AuthenticationError.usernameTaken }
            throw error
        }
    }

    func deleteAccount(accessToken: String) async throws {
        struct Body: Encodable { }
        try await requestIgnoringResponse(path: "/functions/v1/delete-account", method: "POST", body: Body(), accessToken: accessToken)
    }

    private func request<Body: Encodable, Response: Decodable>(path: String, method: String, body: Body, accessToken: String? = nil) async throws -> Response {
        let (data, response) = try await perform(path: path, method: method, body: body, accessToken: accessToken)
        try validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw AuthenticationError.invalidResponse }
        return decoded
    }

    private func requestIgnoringResponse<Body: Encodable>(path: String, method: String, body: Body, accessToken: String? = nil) async throws {
        let (data, response) = try await perform(path: path, method: method, body: body, accessToken: accessToken)
        try validate(response, data: data)
    }

    private func perform<Body: Encodable>(path: String, method: String, body: Body, accessToken: String?) async throws -> (Data, URLResponse) {
        guard let url = URL(string: path, relativeTo: configuration.url) else { throw AuthenticationError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        return try await session.data(for: request)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw AuthenticationError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 429 { throw AuthenticationError.rateLimited }
            let decoded = try? JSONDecoder().decode(SupabaseError.self, from: data)
            if decoded?.code == "weak_password" { throw AuthenticationError.weakPassword }
            throw AuthenticationError.service(message: decoded?.message ?? decoded?.errorDescription ?? "Unable to complete authentication.")
        }
    }

    private struct SupabaseError: Decodable {
        let message: String?; let code: String?; let errorDescription: String?
        enum CodingKeys: String, CodingKey { case message, code; case errorDescription = "error_description" }
    }
}

@MainActor
final class AuthenticationStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isRestoring = true
    @Published private(set) var pendingEmail: String?
    @Published private(set) var pendingUsername: String?
    @Published private(set) var pendingKind: PendingAuthKind?
    @Published var isSkippingForNow: Bool { didSet { UserDefaults.standard.set(isSkippingForNow, forKey: Self.skipKey) } }

    private static let skipKey = "skip-authentication-for-now"
    private static let pendingEmailKey = "pending-auth-email"
    private static let pendingUsernameKey = "pending-auth-username"
    private static let pendingKindKey = "pending-auth-kind"
    private let client: SupabaseAuthClient?
    private let configuration: SupabaseConfiguration?
    private let sessionStore = SecureSessionStore()
    private var refreshTask: Task<Void, Never>?
    private var pendingVerifiedSession: AuthSession?

    init(configuration: SupabaseConfiguration? = .current) {
        self.configuration = configuration
        #if DEBUG
        isSkippingForNow = UserDefaults.standard.bool(forKey: Self.skipKey)
        #else
        isSkippingForNow = false
        #endif
        pendingEmail = UserDefaults.standard.string(forKey: Self.pendingEmailKey)
        pendingUsername = UserDefaults.standard.string(forKey: Self.pendingUsernameKey)
        pendingKind = UserDefaults.standard.string(forKey: Self.pendingKindKey).flatMap(PendingAuthKind.init(rawValue:))
        client = configuration.map { SupabaseAuthClient(configuration: $0) }
        session = sessionStore.load()
        if let session { Task { await restore(session) } } else { isRestoring = false }
    }

    var isConfigured: Bool { client != nil }
    var dataClient: SupabaseDataClient? { configuration.map { SupabaseDataClient(configuration: $0) } }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw AuthenticationError.notConfigured }
        completeAuthentication(try await client.signIn(email: try Self.normalizedEmail(email), password: password))
    }

    func signUp(username: String, email: String, password: String, confirmation: String) async throws {
        guard let client else { throw AuthenticationError.notConfigured }
        let username = UsernamePolicy.normalize(username)
        guard UsernamePolicy.isValid(username) else { throw AuthenticationError.invalidUsername }
        guard PasswordPolicy.isValid(password) else { throw AuthenticationError.weakPassword }
        guard password == confirmation else { throw AuthenticationError.passwordsDoNotMatch }
        let email = try Self.normalizedEmail(email)
        guard try await client.isUsernameAvailable(username) else { throw AuthenticationError.usernameTaken }
        try await client.signUp(email: email, password: password, username: username)
        setPending(email: email, username: username, kind: .signup)
    }

    func checkUsernameAvailability(_ value: String) async throws -> Bool {
        guard let client else { throw AuthenticationError.notConfigured }
        let value = UsernamePolicy.normalize(value)
        guard UsernamePolicy.isValid(value) else { return false }
        return try await client.isUsernameAvailable(value)
    }

    func verifyPendingCode(_ code: String) async throws {
        guard let client, let email = pendingEmail, let kind = pendingKind else { throw AuthenticationError.invalidResponse }
        let verified = try await client.verify(email: email, token: code.filter(\.isNumber), type: kind)
        pendingVerifiedSession = verified
        if kind == .signup {
            guard let username = pendingUsername else { throw AuthenticationError.invalidUsername }
            try await claimPendingUsername(username)
        }
    }

    func claimPendingUsername(_ value: String) async throws {
        guard let client, let verified = pendingVerifiedSession else { throw AuthenticationError.invalidResponse }
        let username = UsernamePolicy.normalize(value)
        guard UsernamePolicy.isValid(username) else { throw AuthenticationError.invalidUsername }
        try await client.claimUsername(username, accessToken: verified.accessToken)
        completeAuthentication(verified)
    }

    func resendPendingCode() async throws {
        guard let client, let email = pendingEmail, let kind = pendingKind else { throw AuthenticationError.invalidResponse }
        if kind == .signup { try await client.resendSignupCode(email: email) } else { try await client.requestPasswordRecovery(email: email) }
    }

    func requestPasswordRecovery(email: String) async throws {
        guard let client else { throw AuthenticationError.notConfigured }
        let email = try Self.normalizedEmail(email)
        try await client.requestPasswordRecovery(email: email)
        setPending(email: email, username: nil, kind: .recovery)
    }

    func finishPasswordRecovery(password: String, confirmation: String) async throws {
        guard let client, let verified = pendingVerifiedSession else { throw AuthenticationError.invalidResponse }
        guard PasswordPolicy.isValid(password) else { throw AuthenticationError.weakPassword }
        guard password == confirmation else { throw AuthenticationError.passwordsDoNotMatch }
        try await client.updatePassword(password, accessToken: verified.accessToken)
        completeAuthentication(verified)
    }

    func deleteAccount(password: String) async throws {
        guard let client, let active = session, let email = active.user.email else { throw AuthenticationError.invalidResponse }
        let fresh = try await client.signIn(email: email, password: password)
        try await client.deleteAccount(accessToken: fresh.accessToken)
        clearLocalAccountData(userID: active.user.id)
        signOut()
    }

    func cancelPendingFlow() { pendingVerifiedSession = nil; clearPending() }

    func signOut() {
        refreshTask?.cancel(); sessionStore.clear(); session = nil; pendingVerifiedSession = nil; clearPending(); isSkippingForNow = false
    }

    private static func normalizedEmail(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.contains("@"), value.split(separator: "@").last?.contains(".") == true else { throw AuthenticationError.invalidEmail }
        return value
    }

    private func setPending(email: String, username: String?, kind: PendingAuthKind) {
        pendingEmail = email; pendingUsername = username; pendingKind = kind
        UserDefaults.standard.set(email, forKey: Self.pendingEmailKey)
        UserDefaults.standard.set(username, forKey: Self.pendingUsernameKey)
        UserDefaults.standard.set(kind.rawValue, forKey: Self.pendingKindKey)
    }

    private func clearPending() {
        pendingEmail = nil; pendingUsername = nil; pendingKind = nil
        [Self.pendingEmailKey, Self.pendingUsernameKey, Self.pendingKindKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func completeAuthentication(_ value: AuthSession) {
        pendingVerifiedSession = nil; clearPending(); sessionStore.save(value); session = value; scheduleRefresh(for: value)
    }

    private func clearLocalAccountData(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: "meal-core-state-v2-\(userID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "household-state-v1-\(userID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "profileAvatarImageData")
    }

    private func restore(_ saved: AuthSession) async {
        defer { isRestoring = false }
        guard saved.expiresAt.timeIntervalSinceNow < 60 else { scheduleRefresh(for: saved); return }
        guard let client else { sessionStore.clear(); session = nil; return }
        do { completeAuthentication(try await client.refresh(saved.refreshToken)) } catch { sessionStore.clear(); session = nil }
    }

    private func scheduleRefresh(for value: AuthSession) {
        refreshTask?.cancel()
        let delay = max(0, value.expiresAt.timeIntervalSinceNow - 60)
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.restore(value)
        }
    }
}

private final class SecureSessionStore {
    private let service = "com.recipeapp.mealcore.auth", account = "supabase-session"
    func load() -> AuthSession? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
    func save(_ value: AuthSession) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        clear()
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary, nil)
    }
    func clear() {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}
