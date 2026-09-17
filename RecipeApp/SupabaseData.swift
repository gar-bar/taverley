import Foundation

actor SupabaseDataClient {
    let configuration: SupabaseConfiguration
    let session: URLSession

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func loadState(for userID: UUID, accessToken: String) async throws -> AccountState {
        async let recipes: [Recipe] = fetch(table: "recipes", userID: userID, accessToken: accessToken)
        async let plans: [MealPlan] = fetch(table: "meal_plans", userID: userID, accessToken: accessToken)
        async let calendarMeals: [CalendarMeal] = fetch(table: "calendar_meals", userID: userID, accessToken: accessToken)
        return try await AccountState(recipes: recipes, plans: plans, calendarMeals: calendarMeals)
    }

    func save(_ state: AccountState, for userID: UUID, accessToken: String) async throws {
        // Feed posts can reference recipes. Upserting preserves those links while
        // still propagating the owner's live recipe edits.
        async let recipeSave: Void = upsert(state.recipes, table: "recipes", userID: userID, accessToken: accessToken)
        async let planSave: Void = replace(state.plans, table: "meal_plans", userID: userID, accessToken: accessToken)
        async let calendarSave: Void = replace(state.calendarMeals, table: "calendar_meals", userID: userID, accessToken: accessToken)
        _ = try await (recipeSave, planSave, calendarSave)
    }

    /// Makes a recipe available to a post immediately, without waiting for the
    /// account store's background sync task.
    func saveRecipe(_ recipe: Recipe, for userID: UUID, accessToken: String) async throws {
        try await upsert([recipe], table: "recipes", userID: userID, accessToken: accessToken)
    }

    private func fetch<Payload: Decodable>(table: String, userID: UUID, accessToken: String) async throws -> [Payload] {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "payload"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode([PayloadRecord<Payload>].self, from: data).map(\.payload)
    }

    private func upsert<Payload: Encodable & Identifiable>(_ values: [Payload], table: String, userID: UUID, accessToken: String) async throws where Payload.ID == UUID {
        guard !values.isEmpty else { return }
        let records = values.map { WriteRecord(id: $0.id, userID: userID, payload: $0) }
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(records)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func replace<Payload: Encodable & Identifiable>(_ values: [Payload], table: String, userID: UUID, accessToken: String) async throws where Payload.ID == UUID {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        try await upsert(values, table: table, userID: userID, accessToken: accessToken)
    }

    func validate(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseError.self, from: data).message) ?? "Unable to sync your changes."
            throw SyncError.service(message: message)
        }
    }

    private struct PayloadRecord<Payload: Decodable>: Decodable { let payload: Payload }

    private struct WriteRecord<Payload: Encodable>: Encodable {
        let id: UUID
        let userID: UUID
        let payload: Payload

        enum CodingKeys: String, CodingKey { case id; case userID = "user_id"; case payload }
    }

    private struct SupabaseError: Decodable { let message: String }
}

enum SyncError: LocalizedError {
    case invalidResponse
    case service(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The sync service sent an invalid response."
        case let .service(message): message
        }
    }
}
