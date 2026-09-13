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
