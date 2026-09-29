import Foundation

enum SocialListKind: String, Hashable {
    case followers
    case following
}

struct SocialPageKey: Hashable {
    var profileID: UUID
    var kind: SocialListKind
    var query: String
}

extension ProfileRelationship {
    func applyingFollowResult(isFollowing: Bool, isRequested: Bool) -> Self {
        var copy = self
        if copy.isFollowing != isFollowing {
            copy.followerCount = max(0, copy.followerCount + (isFollowing ? 1 : -1))
        }
        copy.isFollowing = isFollowing
        copy.isRequested = isRequested
        return copy
    }

    func togglingFollow() -> Self {
        applyingFollowResult(isFollowing: !isFollowing, isRequested: false)
    }
}

enum SocialFollowPolicy {
    static func canFollow(currentUserID: UUID, profileID: UUID) -> Bool { currentUserID != profileID }
}

enum SocialPagePolicy {
    static func merging<Element: Identifiable>(_ existing: [Element], with incoming: [Element]) -> [Element] where Element.ID: Hashable {
        let known = Set(existing.map(\.id))
        return existing + incoming.filter { !known.contains($0.id) }
    }
}

enum SharedRecipePolicy {
    static func recipeIDs(from posts: [FeedPost]) -> [UUID] {
        var seen: Set<UUID> = []
        return posts.compactMap(\.recipeID).filter { seen.insert($0).inserted }
    }
}

extension SupabaseDataClient {
    func fetchFollowingPosts(accessToken: String) async throws -> [FeedPost] {
        let url = configuration.url.appending(path: "rest/v1/rpc/following_feed")
        let records: [SocialFeedPostRecord] = try await socialRequest(url: url, method: "POST", body: EmptyBody(), accessToken: accessToken)
        return records.compactMap(\.post)
    }

    func searchProfiles(_ rawQuery: String, excluding _: UUID, accessToken: String) async throws -> [SocialProfileSummary] {
        let query = SocialSearchPolicy.normalize(rawQuery)
        guard !query.isEmpty else { return [] }
        let url = configuration.url.appending(path: "rest/v1/rpc/search_social_profiles")
        let records: [SocialProfileRecord] = try await socialRequest(
            url: url,
            method: "POST",
            body: SearchProfilesBody(searchText: query, resultLimit: 20),
            accessToken: accessToken
        )
        return records.compactMap(\.summary)
    }

    func follow(profileID: UUID, accessToken: String) async throws -> String {
        let url = configuration.url.appending(path: "rest/v1/rpc/request_follow")
        return try await socialRequest(
            url: url,
            method: "POST",
            body: FollowRequestBody(targetUser: profileID),
            accessToken: accessToken
        )
    }

    func unfollow(profileID: UUID, followerID: UUID, accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/user_follows"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "follower_id", value: "eq.\(followerID.uuidString)"),
            URLQueryItem(name: "followed_id", value: "eq.\(profileID.uuidString)")
        ]
        let _: EmptyResponse = try await socialRequest(url: components.url!, method: "DELETE", body: EmptyBody(), accessToken: accessToken)
    }

    func loadRelationship(profileID: UUID, currentUserID: UUID, accessToken: String) async throws -> ProfileRelationship {
        async let followers = socialCount(
            table: "user_follows",
            filters: [URLQueryItem(name: "followed_id", value: "eq.\(profileID.uuidString)"), URLQueryItem(name: "status", value: "eq.accepted")],
            accessToken: accessToken
        )
        async let following = socialCount(
            table: "user_follows",
            filters: [URLQueryItem(name: "follower_id", value: "eq.\(profileID.uuidString)"), URLQueryItem(name: "status", value: "eq.accepted")],
            accessToken: accessToken
        )
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/user_follows"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "status"),
            URLQueryItem(name: "follower_id", value: "eq.\(currentUserID.uuidString)"),
            URLQueryItem(name: "followed_id", value: "eq.\(profileID.uuidString)")
        ]
        let rows: [FollowStatusRecord] = try await socialGet(components.url!, accessToken: accessToken)
        let status = rows.first?.status
        return try await ProfileRelationship(isFollowing: status == "accepted", isRequested: status == "pending", followerCount: followers, followingCount: following)
    }

    func loadFollowers(
        profileID: UUID, query: String, offset: Int, limit: Int, accessToken: String
    ) async throws -> SocialPage<SocialProfileSummary> {
        try await loadRelationshipProfiles(profileID: profileID, kind: .followers, query: query, offset: offset, limit: limit, accessToken: accessToken)
    }

    func loadFollowing(
        profileID: UUID, query: String, offset: Int, limit: Int, accessToken: String
    ) async throws -> SocialPage<SocialProfileSummary> {
        try await loadRelationshipProfiles(profileID: profileID, kind: .following, query: query, offset: offset, limit: limit, accessToken: accessToken)
    }

    func loadPublicProfileContent(profileID: UUID, accessToken: String) async throws -> PublicProfileContent {
        var profileComponents = URLComponents(url: configuration.url.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        profileComponents.queryItems = [
            URLQueryItem(name: "select", value: "id,display_name,username,is_private"),
            URLQueryItem(name: "id", value: "eq.\(profileID.uuidString)")
        ]
        let profiles: [SocialBasicProfileRecord] = try await socialGet(profileComponents.url!, accessToken: accessToken)
        guard let profile = profiles.first?.profile else { throw SyncError.invalidResponse }

        var postComponents = URLComponents(url: configuration.url.appending(path: "rest/v1/feed_posts"), resolvingAgainstBaseURL: false)!
        postComponents.queryItems = [
            URLQueryItem(name: "select", value: "id,author_id,title,body,recipe_id,photo_paths,created_at"),
            URLQueryItem(name: "author_id", value: "eq.\(profileID.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        let records: [SocialFeedPostRecord] = try await socialGet(postComponents.url!, accessToken: accessToken)
        let posts = records.compactMap(\.post)
        let recipeIDs = SharedRecipePolicy.recipeIDs(from: posts)
        let recipes = try await socialPublishedRecipes(ids: recipeIDs, accessToken: accessToken)
        let items = posts.map { FeedItem(post: $0, author: profile, recipe: $0.recipeID.flatMap { recipes[$0] }) }
        return PublicProfileContent(profile: profile, posts: items, recipes: recipeIDs.compactMap { recipes[$0] })
    }

    func loadFollowRequests(for profileID: UUID, accessToken: String) async throws -> [FollowRequest] {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/user_follows"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "follower_id,created_at"),
            URLQueryItem(name: "followed_id", value: "eq.\(profileID.uuidString)"),
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        let rows: [PendingFollowRequestRecord] = try await socialGet(components.url!, accessToken: accessToken)
        let ids = rows.map(\.followerID)
        guard !ids.isEmpty else { return [] }
        var profileComponents = URLComponents(url: configuration.url.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        profileComponents.queryItems = [
            URLQueryItem(name: "select", value: "id,display_name,username,is_private"),
            URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
        ]
        let profiles: [SocialBasicProfileRecord] = try await socialGet(profileComponents.url!, accessToken: accessToken)
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.compactMap { record in record.profile.map { (record.id, $0) } })
        return rows.compactMap { row in
            guard let requester = profilesByID[row.followerID], let createdAt = SocialDateCoding.date(from: row.createdAt) else { return nil }
            return FollowRequest(requester: requester, createdAt: createdAt)
        }
    }

    func respondToFollowRequest(requesterID: UUID, approve: Bool, accessToken: String) async throws {
        let url = configuration.url.appending(path: "rest/v1/rpc/respond_to_follow_request")
        try await socialRequestIgnoringResponse(
            url: url,
            method: "POST",
            body: RespondToFollowRequestBody(requesterID: requesterID, approve: approve),
            accessToken: accessToken
        )
    }

    private func loadRelationshipProfiles(
        profileID: UUID, kind: SocialListKind, query: String, offset: Int, limit: Int, accessToken: String
    ) async throws -> SocialPage<SocialProfileSummary> {
        let url = configuration.url.appending(path: "rest/v1/rpc/relationship_profiles")
        let records: [RelationshipProfileRecord] = try await socialRequest(
            url: url,
            method: "POST",
            body: RelationshipProfilesBody(
                targetUser: profileID,
                relationshipKind: kind.rawValue,
                searchText: SocialSearchPolicy.normalize(query),
                pageOffset: offset,
                pageLimit: limit
            ),
            accessToken: accessToken
        )
        let total = records.first?.totalCount ?? 0
        let items = records.compactMap(\.summary)
        return SocialPage(items: items, nextOffset: offset + items.count < total ? offset + items.count : nil, totalCount: total)
    }

    private func socialPublishedRecipes(ids: [UUID], accessToken: String) async throws -> [UUID: Recipe] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/recipes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "payload"),
            URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
        ]
        let records: [SocialRecipeRecord] = try await socialGet(components.url!, accessToken: accessToken)
        return Dictionary(uniqueKeysWithValues: records.map { ($0.payload.id, $0.payload) })
    }

    private func socialCount(table: String, filters: [URLQueryItem], accessToken: String) async throws -> Int {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "*")] + filters + [URLQueryItem(name: "limit", value: "0")]
        var request = socialAuthorizedRequest(url: components.url!, accessToken: accessToken)
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let response = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        return response.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int($0) } ?? 0
    }

    private func socialGet<Response: Decodable>(_ url: URL, accessToken: String) async throws -> Response {
        let request = socialAuthorizedRequest(url: url, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func socialRequest<Response: Decodable, Body: Encodable>(
        url: URL, method: String, body: Body, accessToken: String, prefer: String? = nil
    ) async throws -> Response {
        var request = socialAuthorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if method != "DELETE" { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if data.isEmpty { return try JSONDecoder().decode(Response.self, from: Data("{}".utf8)) }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func socialRequestIgnoringResponse<Body: Encodable>(
        url: URL, method: String, body: Body, accessToken: String
    ) async throws {
        var request = socialAuthorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func socialAuthorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var searchResults: [SocialProfileSummary] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?
    @Published private(set) var relationships: [UUID: ProfileRelationship] = [:]
    @Published private(set) var profileContent: [UUID: PublicProfileContent] = [:]
    @Published private(set) var loadingProfiles: Set<UUID> = []
    @Published private(set) var relationshipPages: [SocialPageKey: SocialPage<SocialProfileSummary>] = [:]
    @Published private(set) var pendingFollowIDs: Set<UUID> = []
    @Published private(set) var followRequests: [FollowRequest] = []

    private var client: SupabaseDataClient?
    private var session: AuthSession?

    var currentUserID: UUID? { session?.user.id }

    func activateAccount(_ session: AuthSession, client: SupabaseDataClient) async {
        guard self.session?.accessToken != session.accessToken || self.session?.user.id != session.user.id else { return }
        self.session = session
        self.client = client
        resetState()
        await loadRelationship(for: session.user.id)
        await refreshFollowRequests()
    }

    func deactivateAccount() {
        client = nil
        session = nil
        resetState()
    }

    func search(_ query: String) async {
        guard let client, let session else { searchResults = []; return }
        let normalized = SocialSearchPolicy.normalize(query)
        guard !normalized.isEmpty else { searchResults = []; searchError = nil; isSearching = false; return }
        isSearching = true
        searchError = nil
        do {
            let results = try await client.searchProfiles(normalized, excluding: session.user.id, accessToken: session.accessToken)
            guard !Task.isCancelled else { return }
            searchResults = results
            for result in results { relationships[result.id] = result.relationship }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchError = error.localizedDescription
        }
        if !Task.isCancelled { isSearching = false }
    }

    func loadRelationship(for profileID: UUID) async {
        guard let client, let session else { return }
        do {
            relationships[profileID] = try await client.loadRelationship(profileID: profileID, currentUserID: session.user.id, accessToken: session.accessToken)
        } catch {
            searchError = error.localizedDescription
        }
    }

    func loadProfile(_ profileID: UUID, refresh: Bool = false) async {
        guard let client, let session, refresh || profileContent[profileID] == nil else { return }
        loadingProfiles.insert(profileID)
        defer { loadingProfiles.remove(profileID) }
        do {
            async let content = client.loadPublicProfileContent(profileID: profileID, accessToken: session.accessToken)
            async let relationship = client.loadRelationship(profileID: profileID, currentUserID: session.user.id, accessToken: session.accessToken)
            profileContent[profileID] = try await content
            relationships[profileID] = try await relationship
        } catch {
            searchError = error.localizedDescription
        }
    }

    func toggleFollow(profileID: UUID) async throws {
        guard let client, let session, SocialFollowPolicy.canFollow(currentUserID: session.user.id, profileID: profileID) else {
            throw SyncError.service(message: "You can’t follow yourself.")
        }
        if relationships[profileID] == nil { await loadRelationship(for: profileID) }
        let original = relationships[profileID] ?? ProfileRelationship(isFollowing: false, followerCount: 0, followingCount: 0)
        let cancelling = original.isFollowing || original.isRequested
        relationships[profileID] = original.applyingFollowResult(isFollowing: false, isRequested: false)
        pendingFollowIDs.insert(profileID)
        defer { pendingFollowIDs.remove(profileID) }
        do {
            if cancelling {
                try await client.unfollow(profileID: profileID, followerID: session.user.id, accessToken: session.accessToken)
            } else {
                let result = try await client.follow(profileID: profileID, accessToken: session.accessToken)
                relationships[profileID] = original.applyingFollowResult(isFollowing: result == "accepted", isRequested: result == "pending")
            }
            await loadRelationship(for: profileID)
            await loadRelationship(for: session.user.id)
        } catch {
            relationships[profileID] = original
            throw error
        }
    }

    func refreshFollowRequests() async {
        guard let client, let session else { followRequests = []; return }
        do {
            followRequests = try await client.loadFollowRequests(for: session.user.id, accessToken: session.accessToken)
        } catch {
            searchError = error.localizedDescription
        }
    }

    func respondToFollowRequest(_ request: FollowRequest, approve: Bool) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to manage follow requests.") }
        let previous = followRequests
        followRequests.removeAll { $0.id == request.id }
        do {
            try await client.respondToFollowRequest(requesterID: request.id, approve: approve, accessToken: session.accessToken)
            await loadRelationship(for: session.user.id)
        } catch {
            followRequests = previous
            throw error
        }
    }

    func loadPeople(profileID: UUID, kind: SocialListKind, query: String, reset: Bool = false) async {
        guard let client, let session else { return }
        let key = SocialPageKey(profileID: profileID, kind: kind, query: SocialSearchPolicy.normalize(query))
        var state = relationshipPages[key] ?? SocialPage()
        guard !state.isLoading, let offset = reset ? 0 : state.nextOffset else { return }
        state.isLoading = true
        state.errorMessage = nil
        relationshipPages[key] = state
        do {
            let page = try await (kind == .followers
                ? client.loadFollowers(profileID: profileID, query: key.query, offset: offset, limit: 25, accessToken: session.accessToken)
                : client.loadFollowing(profileID: profileID, query: key.query, offset: offset, limit: 25, accessToken: session.accessToken))
            let items = SocialPagePolicy.merging(reset ? [] : state.items, with: page.items)
            relationshipPages[key] = SocialPage(items: items, nextOffset: page.nextOffset, totalCount: page.totalCount)
            for item in page.items { relationships[item.id] = item.relationship }
        } catch {
            state.isLoading = false
            state.errorMessage = error.localizedDescription
            relationshipPages[key] = state
        }
    }

    func page(profileID: UUID, kind: SocialListKind, query: String) -> SocialPage<SocialProfileSummary> {
        relationshipPages[SocialPageKey(profileID: profileID, kind: kind, query: SocialSearchPolicy.normalize(query))] ?? SocialPage()
    }

    private func resetState() {
        searchResults = []
        isSearching = false
        searchError = nil
        relationships = [:]
        profileContent = [:]
        loadingProfiles = []
        relationshipPages = [:]
        pendingFollowIDs = []
        followRequests = []
    }
}

enum SocialSearchPolicy {
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}

private struct FollowRequestBody: Encodable {
    let targetUser: UUID
    enum CodingKeys: String, CodingKey { case targetUser = "target_user" }
}

private struct FollowStatusRecord: Decodable { let status: String }

private struct PendingFollowRequestRecord: Decodable {
    let followerID: UUID
    let createdAt: String
    enum CodingKeys: String, CodingKey { case followerID = "follower_id"; case createdAt = "created_at" }
}

private struct RespondToFollowRequestBody: Encodable {
    let requesterID: UUID
    let approve: Bool
    enum CodingKeys: String, CodingKey { case requesterID = "requester_id"; case approve }
}

private struct SearchProfilesBody: Encodable {
    let searchText: String
    let resultLimit: Int
    enum CodingKeys: String, CodingKey { case searchText = "search_text"; case resultLimit = "result_limit" }
}

private struct RelationshipProfilesBody: Encodable {
    let targetUser: UUID
    let relationshipKind: String
    let searchText: String
    let pageOffset: Int
    let pageLimit: Int
    enum CodingKeys: String, CodingKey {
        case targetUser = "target_user"
        case relationshipKind = "relationship_kind"
        case searchText = "search_text"
        case pageOffset = "page_offset"
        case pageLimit = "page_limit"
    }
}

private struct SocialBasicProfileRecord: Decodable {
    let id: UUID
    let displayName: String
    let username: String?
    let isPrivate: Bool?
    enum CodingKeys: String, CodingKey { case id, username; case displayName = "display_name"; case isPrivate = "is_private" }
    var profile: UserProfile? {
        guard let username, !username.isEmpty else { return nil }
        return UserProfile(id: id, displayName: displayName.isEmpty ? username : displayName, username: username, isPrivate: isPrivate ?? false)
    }
}

private struct SocialProfileRecord: Decodable {
    let id: UUID
    let displayName: String
    let username: String
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool
    let isRequested: Bool
    let isPrivate: Bool
    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
        case isRequested = "is_requested"
        case isPrivate = "is_private"
    }
    var summary: SocialProfileSummary? {
        guard !username.isEmpty else { return nil }
        return SocialProfileSummary(
            profile: UserProfile(id: id, displayName: displayName.isEmpty ? username : displayName, username: username, isPrivate: isPrivate),
            relationship: ProfileRelationship(isFollowing: isFollowing, isRequested: isRequested, followerCount: followerCount, followingCount: followingCount)
        )
    }
}

private struct RelationshipProfileRecord: Decodable {
    let id: UUID
    let displayName: String
    let username: String
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool
    let isRequested: Bool
    let isPrivate: Bool
    let totalCount: Int
    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
        case isRequested = "is_requested"
        case isPrivate = "is_private"
        case totalCount = "total_count"
    }
    var summary: SocialProfileSummary? {
        SocialProfileRecord(id: id, displayName: displayName, username: username, followerCount: followerCount, followingCount: followingCount, isFollowing: isFollowing, isRequested: isRequested, isPrivate: isPrivate).summary
    }
}

private struct SocialFeedPostRecord: Decodable {
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
    var post: FeedPost? {
        guard let date = SocialDateCoding.date(from: createdAt) else { return nil }
        return FeedPost(id: id, authorID: authorID, title: title, body: body, recipeID: recipeID, photoPaths: Array(photoPaths.prefix(4)), createdAt: date)
    }
}

private struct SocialRecipeRecord: Decodable { let payload: Recipe }

private enum SocialDateCoding {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let standard = ISO8601DateFormatter()
    static func date(from value: String) -> Date? { fractional.date(from: value) ?? standard.date(from: value) }
}
