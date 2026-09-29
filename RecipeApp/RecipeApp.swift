import SwiftUI

@main
struct RecipeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MealStore()
    @StateObject private var feedStore = FeedStore()
    @StateObject private var socialStore = SocialStore()
    @StateObject private var householdStore = HouseholdStore()
    @StateObject private var authentication = AuthenticationStore()

    var body: some Scene {
        WindowGroup {
            AuthenticationGate()
                .environmentObject(store)
                .environmentObject(feedStore)
                .environmentObject(socialStore)
                .environmentObject(householdStore)
                .environmentObject(authentication)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        guard let session = await authentication.refreshIfNeeded(), let dataClient = authentication.dataClient else { return }
                        await store.activateAccount(session, client: dataClient)
                        await feedStore.activateAccount(session, client: dataClient)
                        await socialStore.activateAccount(session, client: dataClient)
                        await householdStore.activateAccount(session, client: dataClient)
                        await householdStore.refresh()
                    }
                }
        }
    }
}
