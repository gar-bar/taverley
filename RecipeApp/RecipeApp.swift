import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var store = MealStore()
    @StateObject private var feedStore = FeedStore()
    @StateObject private var authentication = AuthenticationStore()

    var body: some Scene {
        WindowGroup {
            AuthenticationGate()
                .environmentObject(store)
                .environmentObject(feedStore)
                .environmentObject(authentication)
        }
    }
}
