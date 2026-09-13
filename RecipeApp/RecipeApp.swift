import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var store = MealStore()

    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}
