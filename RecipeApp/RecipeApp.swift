import SwiftUI

@main
struct RecipeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MealStore()
    @StateObject private var feedStore = FeedStore()
    @StateObject private var householdStore = HouseholdStore()
    @StateObject private var authentication = AuthenticationStore()

    var body: some Scene {
        WindowGroup {
            AuthenticationGate()
                .environmentObject(store)
                .environmentObject(feedStore)
                .environmentObject(householdStore)
                .environmentObject(authentication)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, authentication.session != nil else { return }
                    Task { await householdStore.refresh() }
                }
        }
    }
}
