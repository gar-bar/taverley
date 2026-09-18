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
    var calories: Double? { nutrition.first { $0.name.lowercased() == "calories" }?.amount }
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
