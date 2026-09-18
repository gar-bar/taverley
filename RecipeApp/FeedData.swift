import Foundation

struct FeedPayload {
    var posts: [FeedPost]
    var profiles: [UUID: UserProfile]
    var recipes: [UUID: Recipe]
    var likes: [FeedReaction]
    var favouritedPostIDs: Set<UUID>
    var comments: [PostComment]
    var favouritedRecipeIDs: Set<UUID>
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

    func loadFeed(for userID: UUID, accessToken: String) async throws -> FeedPayload {
        var postComponents = URLComponents(url: configuration.url.appending(path: "rest/v1/feed_posts"), resolvingAgainstBaseURL: false)!
        postComponents.queryItems = [
            URLQueryItem(name: "select", value: "id,author_id,title,body,recipe_id,photo_paths,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        let records: [FeedPostRecord] = try await get(postComponents.url!, accessToken: accessToken)
        let posts = records.compactMap(\.post)
        let recipeIDs = Array(Set(posts.compactMap(\.recipeID)))

        async let likes = fetchPostLikes(accessToken: accessToken)
        async let comments = fetchPostComments(accessToken: accessToken)
        async let favouritedPostIDs = fetchFavouritePostIDs(for: userID, accessToken: accessToken)
        async let favouritedRecipeIDs = fetchFavouriteRecipeIDs(for: userID, accessToken: accessToken)

        let resolvedLikes = try await likes
        let resolvedComments = try await comments
        let authorIDs = Array(Set(posts.map(\.authorID) + resolvedComments.map(\.authorID)))
        async let profiles = fetchProfiles(ids: authorIDs, accessToken: accessToken)
        async let recipes = fetchPublishedRecipes(ids: recipeIDs, accessToken: accessToken)
        return try await FeedPayload(
            posts: posts,
            profiles: profiles,
            recipes: recipes,
            likes: resolvedLikes,
            favouritedPostIDs: favouritedPostIDs,
            comments: resolvedComments,
            favouritedRecipeIDs: favouritedRecipeIDs
        )
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

    func createPostLike(postID: UUID, accessToken: String) async throws {
        try await createReaction(table: "post_likes", postID: postID, accessToken: accessToken)
    }

    func deletePostLike(postID: UUID, userID: UUID, accessToken: String) async throws {
        try await deleteReaction(table: "post_likes", postID: postID, userID: userID, accessToken: accessToken)
    }

    func createPostFavourite(postID: UUID, accessToken: String) async throws {
        try await createReaction(table: "post_favourites", postID: postID, accessToken: accessToken)
    }

    func deletePostFavourite(postID: UUID, userID: UUID, accessToken: String) async throws {
        try await deleteReaction(table: "post_favourites", postID: postID, userID: userID, accessToken: accessToken)
    }

    func createRecipeFavourite(recipeID: UUID, accessToken: String) async throws {
        let url = configuration.url.appending(path: "rest/v1/recipe_favourites")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([RecipeFavouriteWriteRecord(recipeID: recipeID)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func deleteRecipeFavourite(recipeID: UUID, userID: UUID, accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/recipe_favourites"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "recipe_id", value: "eq.\(recipeID.uuidString)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func createPostComment(postID: UUID, body: String, accessToken: String) async throws -> PostComment {
        let url = configuration.url.appending(path: "rest/v1/post_comments")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([PostCommentWriteRecord(postID: postID, body: body)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let comment = try JSONDecoder().decode([PostCommentRecord].self, from: data).first?.comment else {
            throw SyncError.invalidResponse
        }
        return comment
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

    private func createReaction(table: String, postID: UUID, accessToken: String) async throws {
        let url = configuration.url.appending(path: "rest/v1/\(table)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([PostReactionWriteRecord(postID: postID)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func deleteReaction(table: String, postID: UUID, userID: UUID, accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "post_id", value: "eq.\(postID.uuidString)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func fetchPostLikes(accessToken: String) async throws -> [FeedReaction] {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/post_likes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "post_id,user_id")]
        let records: [PostReactionRecord] = try await get(components.url!, accessToken: accessToken)
        return records.map(\.reaction)
    }

    private func fetchPostComments(accessToken: String) async throws -> [PostComment] {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/post_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,post_id,author_id,body,created_at"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        let records: [PostCommentRecord] = try await get(components.url!, accessToken: accessToken)
        return records.compactMap(\.comment)
    }

    private func fetchFavouritePostIDs(for userID: UUID, accessToken: String) async throws -> Set<UUID> {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/post_favourites"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "post_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ]
        let records: [PostIDRecord] = try await get(components.url!, accessToken: accessToken)
        return Set(records.map(\.postID))
    }

    private func fetchFavouriteRecipeIDs(for userID: UUID, accessToken: String) async throws -> Set<UUID> {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/recipe_favourites"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "recipe_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ]
        let records: [RecipeIDRecord] = try await get(components.url!, accessToken: accessToken)
        return Set(records.map(\.recipeID))
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

private struct PostReactionRecord: Decodable {
    let postID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
    }

    var reaction: FeedReaction { FeedReaction(postID: postID, userID: userID) }
}

private struct PostReactionWriteRecord: Encodable {
    let postID: UUID

    enum CodingKeys: String, CodingKey { case postID = "post_id" }
}

private struct PostIDRecord: Decodable {
    let postID: UUID
    enum CodingKeys: String, CodingKey { case postID = "post_id" }
}

private struct RecipeIDRecord: Decodable {
    let recipeID: UUID
    enum CodingKeys: String, CodingKey { case recipeID = "recipe_id" }
}

private struct RecipeFavouriteWriteRecord: Encodable {
    let recipeID: UUID
    enum CodingKeys: String, CodingKey { case recipeID = "recipe_id" }
}

private struct PostCommentRecord: Decodable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case postID = "post_id"
        case authorID = "author_id"
        case createdAt = "created_at"
    }

    var comment: PostComment? {
        guard let date = FeedDateCoding.date(from: createdAt) else { return nil }
        return PostComment(id: id, postID: postID, authorID: authorID, body: body, createdAt: date)
    }
}

private struct PostCommentWriteRecord: Encodable {
    let postID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case body
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
    @Published private(set) var likedPostIDs: Set<UUID> = []
    @Published private(set) var favouritedPostIDs: Set<UUID> = []
    @Published private(set) var favouritedRecipeIDs: Set<UUID> = []
    @Published private(set) var commentsByPost: [UUID: [FeedComment]] = [:]
    private var postLikes: [FeedReaction] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var client: SupabaseDataClient?
    private var session: AuthSession?

    var isAuthenticated: Bool { session != nil }
    var currentUserID: UUID? { session?.user.id }

    func activateAccount(_ session: AuthSession, client: SupabaseDataClient) async {
        guard self.session?.accessToken != session.accessToken || self.session?.user.id != session.user.id else { return }
        self.session = session
        self.client = client
        photoData = [:]
        likedPostIDs = []
        favouritedPostIDs = []
        favouritedRecipeIDs = []
        commentsByPost = [:]
        postLikes = []
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
        likedPostIDs = []
        favouritedPostIDs = []
        favouritedRecipeIDs = []
        commentsByPost = [:]
        postLikes = []
        items = FeedSeed.items
        errorMessage = nil
        isLoading = false
    }

    func refresh() async throws {
        guard let client, let session else { return }
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let payload = try await client.loadFeed(for: session.user.id, accessToken: session.accessToken)
            items = payload.posts.compactMap { post in
                guard let author = payload.profiles[post.authorID] else { return nil }
                return FeedItem(post: post, author: author, recipe: post.recipeID.flatMap { payload.recipes[$0] })
            }.sorted { $0.post.createdAt > $1.post.createdAt }
            postLikes = payload.likes
            likedPostIDs = Set(payload.likes.compactMap { $0.userID == session.user.id ? $0.postID : nil })
            favouritedPostIDs = payload.favouritedPostIDs
            favouritedRecipeIDs = payload.favouritedRecipeIDs
            commentsByPost = Dictionary(grouping: payload.comments.compactMap { comment in
                guard let author = payload.profiles[comment.authorID] else { return nil }
                return FeedComment(comment: comment, author: author)
            }, by: { $0.comment.postID })
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
        postLikes.removeAll { $0.postID == post.id }
        likedPostIDs.remove(post.id)
        favouritedPostIDs.remove(post.id)
        commentsByPost[post.id] = nil
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

    func likeCount(for postID: UUID) -> Int {
        postLikes.count { $0.postID == postID }
    }

    func comments(for postID: UUID) -> [FeedComment] {
        commentsByPost[postID] ?? []
    }

    func togglePostLike(postID: UUID) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to like posts.") }
        if likedPostIDs.contains(postID) {
            try await client.deletePostLike(postID: postID, userID: session.user.id, accessToken: session.accessToken)
            likedPostIDs.remove(postID)
            postLikes.removeAll { $0.postID == postID && $0.userID == session.user.id }
        } else {
            try await client.createPostLike(postID: postID, accessToken: session.accessToken)
            likedPostIDs.insert(postID)
            postLikes.append(FeedReaction(postID: postID, userID: session.user.id))
        }
    }

    func togglePostFavourite(postID: UUID) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to favourite posts.") }
        if favouritedPostIDs.contains(postID) {
            try await client.deletePostFavourite(postID: postID, userID: session.user.id, accessToken: session.accessToken)
            favouritedPostIDs.remove(postID)
        } else {
            try await client.createPostFavourite(postID: postID, accessToken: session.accessToken)
            favouritedPostIDs.insert(postID)
        }
    }

    func toggleRecipeFavourite(recipeID: UUID) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to favourite recipes.") }
        if favouritedRecipeIDs.contains(recipeID) {
            try await client.deleteRecipeFavourite(recipeID: recipeID, userID: session.user.id, accessToken: session.accessToken)
            favouritedRecipeIDs.remove(recipeID)
        } else {
            try await client.createRecipeFavourite(recipeID: recipeID, accessToken: session.accessToken)
            favouritedRecipeIDs.insert(recipeID)
        }
    }

    func addComment(to postID: UUID, body: String) async throws {
        guard let client, let session, let currentProfile else {
            throw SyncError.service(message: "Complete your profile before commenting.")
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw SyncError.service(message: "Write a comment before posting.") }
        let comment = try await client.createPostComment(postID: postID, body: trimmedBody, accessToken: session.accessToken)
        let item = FeedComment(comment: comment, author: currentProfile)
        commentsByPost[postID, default: []].append(item)
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
