import Foundation
import Combine

final class MealStore: ObservableObject {
    private let key = "meal-core-state-v1"
    @Published var recipes: [Recipe] = [] { didSet { persist() } }
    @Published var plans: [MealPlan] = [] { didSet { persist() } }
    @Published var calendarMeals: [CalendarMeal] = [] { didSet { persist() } }

    init() { load() }

    func recipe(_ id: UUID) -> Recipe? { recipes.first { $0.id == id } }
    func save(recipe: Recipe) { if let i = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[i] = recipe } else { recipes.insert(recipe, at: 0) } }
    func save(plan: MealPlan) { if let i = plans.firstIndex(where: { $0.id == plan.id }) { plans[i] = plan } else { plans.insert(plan, at: 0) } }
    func schedule(recipeID: UUID, on date: Date, type: MealType, replacing: Bool = false, assignmentID: UUID? = nil) {
        let day = Calendar.current.startOfDay(for: date)
        if replacing { calendarMeals.removeAll { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.mealType == type } }
        calendarMeals.append(CalendarMeal(date: day, mealType: type, recipeID: recipeID, assignmentID: assignmentID))
    }
    func apply(plan: MealPlan, from start: Date, through end: Date, replaceExisting: Bool) {
        let assignment = UUID(); let calendar = Calendar.current
        guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day, days >= 0 else { return }
        for offset in 0...days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let planDay = offset % max(1, plan.weekCount * 7)
            let week = planDay / 7 + 1; let weekday = planDay % 7 + 1
            for meal in plan.meals where meal.week == week && meal.weekday == weekday { schedule(recipeID: meal.recipeID, on: date, type: meal.mealType, replacing: replaceExisting, assignmentID: assignment) }
        }
    }
    func meals(on date: Date) -> [CalendarMeal] { calendarMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.mealType.sortOrder < $1.mealType.sortOrder } }
    private func persist() { let state = Persisted(recipes: recipes, plans: plans, calendarMeals: calendarMeals); if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) } }
    private func load() { guard let data = UserDefaults.standard.data(forKey: key), let state = try? JSONDecoder().decode(Persisted.self, from: data) else { recipes = SeedData.recipes; plans = [SeedData.plan(recipes: recipes)]; return }; recipes = state.recipes; plans = state.plans; calendarMeals = state.calendarMeals }
    private struct Persisted: Codable { var recipes: [Recipe]; var plans: [MealPlan]; var calendarMeals: [CalendarMeal] }
}

enum SeedData {
    static let recipes = [Recipe(title: "Apple Pie", summary: "A warm, flaky family dessert.", author: "Elisa", servings: 6, tags: ["Dessert", "Baking"], ingredients: [Ingredient(name: "all-purpose flour", quantity: 1.5, unit: "cups"), Ingredient(name: "apples", quantity: 5, unit: ""), Ingredient(name: "butter", quantity: 3, unit: "tbsp")], steps: [RecipeStep(text: "Prepare the crust and line a pie dish."), RecipeStep(text: "Fill with seasoned apples and bake until golden.")], nutrition: [NutritionFact(name: "Calories", amount: 320, unit: "kcal")]), Recipe(title: "Garden Toast", summary: "Fast, bright and filling.", author: "Elisa", servings: 2, tags: ["Breakfast", "Vegetarian"], ingredients: [Ingredient(name: "sourdough", quantity: 2, unit: "slices"), Ingredient(name: "avocado", quantity: 1, unit: "")], steps: [RecipeStep(text: "Toast bread and top with avocado.")], nutrition: [NutritionFact(name: "Calories", amount: 280, unit: "kcal")])]
    static func plan(recipes: [Recipe]) -> MealPlan { MealPlan(name: "Weekday Favorites", tags: ["Easy"], weekCount: 1, meals: [PlanMeal(week: 1, weekday: 2, mealType: .breakfast, recipeID: recipes[1].id), PlanMeal(week: 1, weekday: 2, mealType: .dinner, recipeID: recipes[0].id)]) }
}
