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

struct FeedItem: Identifiable {
    var post: FeedPost
    var author: UserProfile
    var recipe: Recipe?

    var id: UUID { post.id }

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchable = [
            author.displayName,
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
