import Foundation

enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast = "Breakfast", snack = "Snack", lunch = "Lunch", secondSnack = "Second Snack", dinner = "Dinner"
    var id: String { rawValue }
    var displayName: String { self == .secondSnack ? "Snack" : rawValue }
    var sortOrder: Int { switch self { case .breakfast: 0; case .snack: 1; case .lunch: 2; case .secondSnack: 3; case .dinner: 4 } }
    var symbol: String { switch self { case .breakfast: "sunrise.fill"; case .snack, .secondSnack: "leaf.fill"; case .lunch: "sun.max.fill"; case .dinner: "moon.stars.fill" } }
}

struct Ingredient: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var quantity: Double; var unit: String
    var display: String { "\(quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit) \(name)" }
}

struct RecipeStep: Identifiable, Codable, Hashable { var id = UUID(); var text: String }
struct NutritionFact: Identifiable, Codable, Hashable { var id = UUID(); var name: String; var amount: Double; var unit: String }

struct Recipe: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var summary: String; var author: String; var servings: Int
    var tags: [String]; var ingredients: [Ingredient]; var steps: [RecipeStep]; var nutrition: [NutritionFact]; var imageData: Data? = nil
    var notes: String = ""; var createdAt = Date()
    /// Optional so existing account caches and Supabase payloads remain compatible.
    var prepTimeMinutes: Int? = nil
    var cookTimeMinutes: Int? = nil
    var calories: Double? { nutrition.first { $0.name.lowercased() == "calories" }?.amount }
    var totalTimeMinutes: Int? {
        let parts = [prepTimeMinutes, cookTimeMinutes].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}

/// Keeps the persisted recipe representation simple while making tag identity
/// consistent everywhere it is displayed, edited, and filtered.
enum RecipeTagPolicy {
    static let starterTags = [
        "Breakfast", "Brunch", "Lunch", "Dinner", "Dessert", "Vegetarian",
        "Vegan", "Dairy Free", "Gluten Free", "Healthy"
    ]
    static let mealPlanStarterTags = ["Easy", "Family", "Weeknight", "Weekend", "Meal Prep", "Favourites"]

    static func key(for tag: String) -> String {
        clean(tag).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    static func clean(_ tag: String) -> String {
        tag.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        let starterByKey = Dictionary(uniqueKeysWithValues: starterTags.map { (key(for: $0), $0) })
        return tags.compactMap { rawTag in
            let cleaned = clean(rawTag)
            let tagKey = key(for: cleaned)
            guard !tagKey.isEmpty, seen.insert(tagKey).inserted else { return nil }
            return starterByKey[tagKey] ?? cleaned
        }
    }

    static func catalog(from recipes: [Recipe]) -> [String] {
        normalized(starterTags + recipes.flatMap(\.tags))
    }

    static func mealPlanCatalog(from plans: [MealPlan]) -> [String] {
        normalized(mealPlanStarterTags + plans.flatMap(\.tags))
    }

    static func matchesAll(_ recipe: Recipe, selectedTags: Set<String>) -> Bool {
        matchesAll(recipe.tags, selectedTags: selectedTags)
    }

    static func matchesAll(_ tags: [String], selectedTags: Set<String>) -> Bool {
        guard !selectedTags.isEmpty else { return true }
        let tagKeys = Set(tags.map(key(for:)))
        return selectedTags.allSatisfy { tagKeys.contains(key(for: $0)) }
    }

    static func matchesSearch(_ recipe: Recipe, query: String) -> Bool {
        let query = clean(query)
        guard !query.isEmpty else { return true }
        let searchable = [recipe.title, recipe.author] + recipe.tags + recipe.ingredients.map { $0.name }
        return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func matches(_ recipe: Recipe, query: String, selectedTags: Set<String>) -> Bool {
        matchesSearch(recipe, query: query) && matchesAll(recipe, selectedTags: selectedTags)
    }
}

struct PlanMeal: Identifiable, Codable, Hashable {
    var id = UUID(); var week: Int; var weekday: Int; var mealType: MealType; var recipeID: UUID; var order: Int = 0
}

struct MealPlan: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var tags: [String]; var weekCount: Int; var meals: [PlanMeal]; var imageData: Data? = nil; var createdAt = Date()
}

struct CalendarMeal: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var mealType: MealType; var recipeID: UUID; var assignmentID: UUID?
}

struct UserProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var username: String
    /// Profiles default to public so locally cached profiles created before the
    /// privacy setting existed continue to decode safely.
    var isPrivate: Bool = false

    enum CodingKeys: String, CodingKey { case id, displayName, username, isPrivate }

    init(id: UUID, displayName: String, username: String, isPrivate: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.isPrivate = isPrivate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        username = try values.decode(String.self, forKey: .username)
        isPrivate = try values.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
    }
}

struct UserFollow: Codable, Hashable {
    var followerID: UUID
    var followedID: UUID
    var createdAt: Date
}

struct ProfileRelationship: Hashable {
    var isFollowing: Bool
    var isRequested: Bool = false
    var followerCount: Int
    var followingCount: Int
}

struct SocialProfileSummary: Identifiable, Hashable {
    var profile: UserProfile
    var relationship: ProfileRelationship
    var id: UUID { profile.id }
}

struct PublicProfileContent: Hashable {
    var profile: UserProfile
    var posts: [FeedItem]
    var recipes: [Recipe]
}

struct FollowRequest: Identifiable, Hashable {
    var requester: UserProfile
    var createdAt: Date
    var id: UUID { requester.id }
}

struct SocialPage<Element: Identifiable & Hashable>: Hashable where Element.ID: Hashable {
    var items: [Element] = []
    var nextOffset: Int? = 0
    var totalCount = 0
    var isLoading = false
    var errorMessage: String?

    var hasMore: Bool { nextOffset != nil }
}

struct FeedPost: Identifiable, Codable, Hashable {
    var id = UUID()
    var authorID: UUID
    var title: String
    var body: String
    var recipeID: UUID?
    var photoPaths: [String]
    var createdAt = Date()

    var isValidForPublishing: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photoPaths.count <= 4
    }
}

struct PostComment: Identifiable, Codable, Hashable {
    var id: UUID
    var postID: UUID
    var authorID: UUID
    var body: String
    var createdAt: Date
}

struct FeedComment: Identifiable, Hashable {
    var comment: PostComment
    var author: UserProfile

    var id: UUID { comment.id }
}

struct FeedReaction: Hashable {
    var postID: UUID
    var userID: UUID
}

struct FeedItem: Identifiable, Hashable {
    var post: FeedPost
    var author: UserProfile
    var recipe: Recipe?

    var id: UUID { post.id }

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchable = [
            author.username,
            "@\(author.username)",
            post.title,
            post.body,
            recipe?.title ?? "",
            recipe?.ingredients.map(\.display).joined(separator: " ") ?? ""
        ]
        return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum FavouriteKind: String, CaseIterable, Identifiable {
    case recipes
    case posts

    var id: String { rawValue }
    var title: String { self == .recipes ? "Recipes" : "Posts" }
}

enum HouseholdRole: String, Codable, Hashable {
    case owner
    case member
}

enum HouseholdInvitationStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case revoked
    case expired
}

enum CalendarScope: String, CaseIterable, Identifiable {
    case personal = "Personal"
    case household = "Household"

    var id: Self { self }
}

struct Household: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var ownerID: UUID
    var createdAt: Date
    var updatedAt: Date
}

struct HouseholdMember: Identifiable, Codable, Hashable {
    var householdID: UUID
    var userID: UUID
    var role: HouseholdRole
    var joinedAt: Date
    var profile: UserProfile

    var id: UUID { userID }
}

struct HouseholdInvitation: Identifiable, Codable, Hashable {
    var id: UUID
    var householdID: UUID
    var householdName: String
    var inviter: UserProfile
    var invitee: UserProfile?
    var inviteeID: UUID
    var status: HouseholdInvitationStatus
    var createdAt: Date
    var expiresAt: Date
    var respondedAt: Date?

    var isExpired: Bool { expiresAt <= Date() }
    var canRespond: Bool { status == .pending && !isExpired }
}

struct HouseholdRecipe: Identifiable, Codable, Hashable {
    var householdID: UUID
    var sourceRecipeID: UUID?
    var createdBy: UUID?
    var updatedBy: UUID?
    var version: Int
    var recipe: Recipe
    var updatedAt: Date

    var id: UUID { recipe.id }
}

struct HouseholdMealPlan: Identifiable, Codable, Hashable {
    var householdID: UUID
    var sourcePlanID: UUID?
    var createdBy: UUID?
    var updatedBy: UUID?
    var version: Int
    var plan: MealPlan
    var updatedAt: Date

    var id: UUID { plan.id }
}

struct HouseholdCalendarMeal: Identifiable, Codable, Hashable {
    var id: UUID
    var householdID: UUID
    var date: Date
    var mealType: MealType
    var recipeID: UUID
    var assignmentID: UUID?
    var createdBy: UUID?
    var updatedBy: UUID?
    var updatedAt: Date
}

enum HouseholdConflictPolicy {
    static func isCurrent(localVersion: Int, remoteVersion: Int) -> Bool {
        localVersion == remoteVersion
    }
}

enum HouseholdSharingPolicy {
    static func copy(_ recipe: Recipe, id: UUID = UUID()) -> Recipe {
        var copy = recipe
        copy.id = id
        copy.createdAt = Date()
        return copy
    }

    static func copy(_ plan: MealPlan, id: UUID = UUID(), recipeIDs: [UUID: UUID]) -> MealPlan {
        var copy = plan
        copy.id = id
        copy.createdAt = Date()
        copy.meals = plan.meals.compactMap { meal in
            guard let recipeID = recipeIDs[meal.recipeID] else { return nil }
            var copiedMeal = meal
            copiedMeal.recipeID = recipeID
            return copiedMeal
        }
        return copy
    }
}

enum HouseholdCalendarPolicy {
    static func upserting(_ meal: HouseholdCalendarMeal, into meals: [HouseholdCalendarMeal], calendar: Calendar = .current) -> [HouseholdCalendarMeal] {
        meals.filter { !calendar.isDate($0.date, inSameDayAs: meal.date) || $0.mealType != meal.mealType } + [meal]
    }
}

struct FavouritePage<Item> {
    var items: [Item]
    var nextOffset: Int?
    var totalCount: Int
}

struct FavouriteListState<Item: Identifiable> {
    var items: [Item] = []
    var nextOffset: Int? = 0
    var totalCount = 0
    var isLoading = false
    var errorMessage: String?
    var hasLoaded = false

    var hasMore: Bool { nextOffset != nil }
}

enum UsernamePolicy {
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalize(value)
        guard (3...30).contains(normalized.count) else { return false }
        return normalized.range(of: "^[a-z0-9._]+$", options: .regularExpression) != nil
    }

    static func suggestion(from email: String?) -> String {
        let localPart = email?.split(separator: "@").first.map(String.init) ?? "cook"
        let allowed = localPart.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
        let padded = allowed.count >= 3 ? allowed : "\(allowed)cook"
        return String(padded.prefix(30))
    }
}
