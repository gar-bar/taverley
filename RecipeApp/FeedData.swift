import Foundation

struct FeedPayload {
    var posts: [FeedPost]
    var profiles: [UUID: UserProfile]
    var recipes: [UUID: Recipe]
}

extension SupabaseDataClient {
    func loadCurrentProfile(for userID: UUID, accessToken: String) async throws -> UserProfile? {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,display_name,username"),
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")
        ]
        let records: [ProfileRecord] = try await get(components.url!, accessToken: accessToken)
        return records.first?.profile
    }

    func saveProfile(_ profile: UserProfile, accessToken: String) async throws -> UserProfile {
        let url = configuration.url.appending(path: "rest/v1/profiles")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([ProfileRecord(profile)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let saved = try JSONDecoder().decode([ProfileRecord].self, from: data).first?.profile else {
            throw SyncError.invalidResponse
        }
        return saved
    }

    func loadFeed(accessToken: String) async throws -> FeedPayload {
        var postComponents = URLComponents(url: configuration.url.appending(path: "rest/v1/feed_posts"), resolvingAgainstBaseURL: false)!
        postComponents.queryItems = [
            URLQueryItem(name: "select", value: "id,author_id,title,body,recipe_id,photo_paths,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        let records: [FeedPostRecord] = try await get(postComponents.url!, accessToken: accessToken)
        let posts = records.compactMap(\.post)
        let authorIDs = Array(Set(posts.map(\.authorID)))
        let recipeIDs = Array(Set(posts.compactMap(\.recipeID)))

        async let profiles = fetchProfiles(ids: authorIDs, accessToken: accessToken)
        async let recipes = fetchPublishedRecipes(ids: recipeIDs, accessToken: accessToken)
        return try await FeedPayload(posts: posts, profiles: profiles, recipes: recipes)
    }

    func createPost(_ post: FeedPost, accessToken: String) async throws -> FeedPost {
        let url = configuration.url.appending(path: "rest/v1/feed_posts")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        // The server, rather than the device, supplies author_id and timestamps.
        // This keeps post ownership tied to the JWT that made the request.
        request.httpBody = try JSONEncoder().encode([FeedPostInsertRecord(post)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let saved = try JSONDecoder().decode([FeedPostRecord].self, from: data).first?.post else {
            throw SyncError.invalidResponse
        }
        return saved
    }

    func updatePost(_ post: FeedPost, accessToken: String) async throws -> FeedPost {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/feed_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(post.id.uuidString)")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(FeedPostUpdateRecord(post))
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let saved = try JSONDecoder().decode([FeedPostRecord].self, from: data).first?.post else {
            throw SyncError.invalidResponse
        }
        return saved
    }

    func deletePost(id: UUID, accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/feed_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func uploadPostPhoto(_ data: Data, path: String, accessToken: String) async throws {
        let url = configuration.url.appending(path: "storage/v1/object/post-photos/\(path)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        try validate(response, data: responseData)
    }

    func downloadPostPhoto(path: String, accessToken: String) async throws -> Data {
        let url = configuration.url.appending(path: "storage/v1/object/authenticated/post-photos/\(path)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
    }

    func deletePostPhoto(path: String, accessToken: String) async throws {
        let url = configuration.url.appending(path: "storage/v1/object/post-photos/\(path)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func fetchProfiles(ids: [UUID], accessToken: String) async throws -> [UUID: UserProfile] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,display_name,username"),
            URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
        ]
        let records: [ProfileRecord] = try await get(components.url!, accessToken: accessToken)
        return Dictionary(uniqueKeysWithValues: records.compactMap { record in
            guard let profile = record.profile else { return nil }
            return (profile.id, profile)
        })
    }

    private func fetchPublishedRecipes(ids: [UUID], accessToken: String) async throws -> [UUID: Recipe] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/recipes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "payload"),
            URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
        ]
        let records: [PublishedRecipeRecord] = try await get(components.url!, accessToken: accessToken)
        return Dictionary(uniqueKeysWithValues: records.map { ($0.payload.id, $0.payload) })
    }

    private func get<Response: Decodable>(_ url: URL, accessToken: String) async throws -> Response {
        let request = authorizedRequest(url: url, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private struct ProfileRecord: Codable {
    let id: UUID
    let displayName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
    }

    init(_ profile: UserProfile) {
        id = profile.id
        displayName = profile.displayName
        username = profile.username
    }

    var profile: UserProfile? {
        guard let username, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return UserProfile(id: id, displayName: displayName, username: username)
    }
}

private struct FeedPostRecord: Codable {
    let id: UUID
    let authorID: UUID
    let title: String
    let body: String
    let recipeID: UUID?
    let photoPaths: [String]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case authorID = "author_id"
        case recipeID = "recipe_id"
        case photoPaths = "photo_paths"
        case createdAt = "created_at"
    }

    init(_ post: FeedPost) {
        id = post.id
        authorID = post.authorID
        title = post.title
        body = post.body
        recipeID = post.recipeID
        photoPaths = Array(post.photoPaths.prefix(4))
        createdAt = FeedDateCoding.string(from: post.createdAt)
    }

    var post: FeedPost? {
        guard let date = FeedDateCoding.date(from: createdAt) else { return nil }
        return FeedPost(id: id, authorID: authorID, title: title, body: body, recipeID: recipeID, photoPaths: Array(photoPaths.prefix(4)), createdAt: date)
    }
}

private struct FeedPostInsertRecord: Encodable {
    let id: UUID
    let title: String
    let body: String
    let recipeID: UUID?
    let photoPaths: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case recipeID = "recipe_id"
        case photoPaths = "photo_paths"
    }

    init(_ post: FeedPost) {
        id = post.id
        title = post.title
        body = post.body
        recipeID = post.recipeID
        photoPaths = Array(post.photoPaths.prefix(4))
    }
}

private struct FeedPostUpdateRecord: Encodable {
    let title: String
    let body: String
    let recipeID: UUID?
    let photoPaths: [String]

    enum CodingKeys: String, CodingKey {
        case title, body
        case recipeID = "recipe_id"
        case photoPaths = "photo_paths"
    }

    init(_ post: FeedPost) {
        title = post.title
        body = post.body
        recipeID = post.recipeID
        photoPaths = Array(post.photoPaths.prefix(4))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        if let recipeID {
            try container.encode(recipeID, forKey: .recipeID)
        } else {
            try container.encodeNil(forKey: .recipeID)
        }
        try container.encode(photoPaths, forKey: .photoPaths)
    }
}

private struct PublishedRecipeRecord: Decodable { let payload: Recipe }

private enum FeedDateCoding {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let standard = ISO8601DateFormatter()

    static func string(from date: Date) -> String { fractional.string(from: date) }
    static func date(from value: String) -> Date? { fractional.date(from: value) ?? standard.date(from: value) }
}

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var items: [FeedItem] = FeedSeed.items
    @Published private(set) var currentProfile: UserProfile?
    @Published private(set) var photoData: [String: Data] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var client: SupabaseDataClient?
    private var session: AuthSession?

    var isAuthenticated: Bool { session != nil }
    var currentUserID: UUID? { session?.user.id }

    func activateAccount(_ session: AuthSession, client: SupabaseDataClient) async {
        guard self.session?.user.id != session.user.id else { return }
        self.session = session
        self.client = client
        photoData = [:]
        isLoading = true
        defer { isLoading = false }
        do {
            currentProfile = try await client.loadCurrentProfile(for: session.user.id, accessToken: session.accessToken)
            try await refresh()
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    func deactivateAccount() {
        client = nil
        session = nil
        currentProfile = nil
        photoData = [:]
        items = FeedSeed.items
        errorMessage = nil
        isLoading = false
    }

    func refresh() async throws {
        guard let client, let session else { return }
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let payload = try await client.loadFeed(accessToken: session.accessToken)
            items = payload.posts.compactMap { post in
                guard let author = payload.profiles[post.authorID] else { return nil }
                return FeedItem(post: post, author: author, recipe: post.recipeID.flatMap { payload.recipes[$0] })
            }.sorted { $0.post.createdAt > $1.post.createdAt }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func saveProfile(displayName: String, username: String) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to create a profile.") }
        let profile = UserProfile(
            id: session.user.id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: UsernamePolicy.normalize(username)
        )
        guard !profile.displayName.isEmpty, UsernamePolicy.isValid(profile.username) else {
            throw SyncError.service(message: "Enter a display name and a valid username.")
        }
        currentProfile = try await client.saveProfile(profile, accessToken: session.accessToken)
    }

    func publish(title: String, body: String, recipe: Recipe?, photos: [Data]) async throws {
        guard let client, let session, let currentProfile else {
            throw SyncError.service(message: "Complete your profile before publishing.")
        }
        let postID = UUID()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = photos.prefix(4).enumerated().map { index, _ in
            "\(session.user.id.uuidString.lowercased())/\(postID.uuidString.lowercased())/\(index).jpg"
        }
        let draft = FeedPost(
            id: postID,
            authorID: session.user.id,
            title: trimmedTitle,
            body: trimmedBody,
            recipeID: recipe?.id,
            photoPaths: paths,
            createdAt: Date()
        )
        guard draft.isValidForPublishing else { throw SyncError.service(message: "Add a title and post details before publishing.") }

        var uploaded: [String] = []
        do {
            // A linked recipe must exist remotely before the post policy will
            // accept its foreign key. This also syncs newly-created recipes
            // immediately instead of relying on background account sync.
            if let recipe {
                try await client.saveRecipe(recipe, for: session.user.id, accessToken: session.accessToken)
            }
            for (data, path) in zip(photos.prefix(4), paths) {
                try await client.uploadPostPhoto(data, path: path, accessToken: session.accessToken)
                uploaded.append(path)
            }
            let saved = try await client.createPost(draft, accessToken: session.accessToken)
            items.insert(FeedItem(post: saved, author: currentProfile, recipe: recipe), at: 0)
            for (path, data) in zip(paths, photos) { photoData[path] = data }
        } catch {
            for path in uploaded { try? await client.deletePostPhoto(path: path, accessToken: session.accessToken) }
            throw error
        }
    }

    func update(
        post: FeedPost,
        title: String,
        body: String,
        recipe: Recipe?,
        retainedPhotoPaths: [String],
        newPhotos: [Data]
    ) async throws {
        guard let client, let session, post.authorID == session.user.id else {
            throw SyncError.service(message: "Only the post author can edit this post.")
        }

        let keptPaths = Array(retainedPhotoPaths.prefix(4))
        let availablePhotoSlots = max(0, 4 - keptPaths.count)
        let pendingPhotos = Array(newPhotos.prefix(availablePhotoSlots))
        let newPaths = pendingPhotos.map { _ in
            "\(session.user.id.uuidString.lowercased())/\(post.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        }
        let updated = FeedPost(
            id: post.id,
            authorID: post.authorID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            recipeID: recipe?.id,
            photoPaths: keptPaths + newPaths,
            createdAt: post.createdAt
        )
        guard updated.isValidForPublishing else {
            throw SyncError.service(message: "Add a title and post details before saving.")
        }

        var uploaded: [String] = []
        do {
            if let recipe {
                try await client.saveRecipe(recipe, for: session.user.id, accessToken: session.accessToken)
            }
            for (data, path) in zip(pendingPhotos, newPaths) {
                try await client.uploadPostPhoto(data, path: path, accessToken: session.accessToken)
                uploaded.append(path)
            }

            let saved = try await client.updatePost(updated, accessToken: session.accessToken)
            if let index = items.firstIndex(where: { $0.post.id == post.id }) {
                let author = items[index].author
                items[index] = FeedItem(post: saved, author: author, recipe: recipe)
            }
            for (path, data) in zip(newPaths, pendingPhotos) { photoData[path] = data }

            let removedPaths = Set(post.photoPaths).subtracting(keptPaths)
            for path in removedPaths {
                try? await client.deletePostPhoto(path: path, accessToken: session.accessToken)
                photoData[path] = nil
            }
        } catch {
            for path in uploaded { try? await client.deletePostPhoto(path: path, accessToken: session.accessToken) }
            throw error
        }
    }

    func delete(post: FeedPost) async throws {
        guard let client, let session, post.authorID == session.user.id else {
            throw SyncError.service(message: "Only the post author can delete this post.")
        }
        try await client.deletePost(id: post.id, accessToken: session.accessToken)
        items.removeAll { $0.post.id == post.id }
        for path in post.photoPaths {
            try? await client.deletePostPhoto(path: path, accessToken: session.accessToken)
            photoData[path] = nil
        }
    }

    func loadPhoto(path: String) async {
        guard !path.hasPrefix("asset:"), photoData[path] == nil, let client, let session else { return }
        if let data = try? await client.downloadPostPhoto(path: path, accessToken: session.accessToken) {
            photoData[path] = data
        }
    }
}

enum FeedSeed {
    private static let authorID = UUID(uuidString: "7D5FA3C7-15DD-4F4A-8C70-E52B1E0BC219")!
    private static let profile = UserProfile(id: authorID, displayName: "Real Person", username: "person")

    static let items: [FeedItem] = [
        FeedItem(
            post: FeedPost(authorID: authorID, title: "A cozy apple pie for the weekend", body: "This flaky family dessert is simple, warm, and made for sharing.", recipeID: SeedData.recipes.first?.id, photoPaths: ["asset:FigmaRecipe2", "asset:FigmaRecipe1", "asset:FigmaRecipe3"], createdAt: Date()),
            author: profile,
            recipe: SeedData.recipes.first
        ),
        FeedItem(
            post: FeedPost(authorID: authorID, title: "My fastest garden toast", body: "A bright breakfast that comes together in a few minutes.", recipeID: SeedData.recipes.last?.id, photoPaths: ["asset:FigmaRecipe3", "asset:FigmaRecipe4"], createdAt: Date().addingTimeInterval(-3_600)),
            author: profile,
            recipe: SeedData.recipes.last
        )
    ]
}
