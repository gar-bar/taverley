import Foundation
import Combine

struct HouseholdSnapshot: Codable {
    var household: Household?
    var members: [HouseholdMember]
    var invitations: [HouseholdInvitation]
    var recipes: [HouseholdRecipe]
    var plans: [HouseholdMealPlan]
    var calendarMeals: [HouseholdCalendarMeal]
}

extension SupabaseDataClient {
    func loadHouseholdSnapshot(for userID: UUID, accessToken: String) async throws -> HouseholdSnapshot {
        async let invitations = loadHouseholdInvitations(for: userID, accessToken: accessToken)
        let membership: [HouseholdMembershipRecord] = try await householdGet(
            table: "household_members",
            query: [
                URLQueryItem(name: "select", value: "household_id,user_id,role,joined_at"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ],
            accessToken: accessToken
        )
        guard let ownMembership = membership.first else {
            let receivedInvitations = try await invitations
            return HouseholdSnapshot(household: nil, members: [], invitations: receivedInvitations, recipes: [], plans: [], calendarMeals: [])
        }
        let householdID = ownMembership.householdID
        async let householdRecords: [HouseholdRecord] = householdGet(
            table: "households",
            query: [URLQueryItem(name: "id", value: "eq.\(householdID.uuidString)")],
            accessToken: accessToken
        )
        async let memberRecords: [HouseholdMembershipRecord] = householdGet(
            table: "household_members",
            query: [
                URLQueryItem(name: "select", value: "household_id,user_id,role,joined_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdID.uuidString)"),
                URLQueryItem(name: "order", value: "joined_at.asc")
            ],
            accessToken: accessToken
        )
        async let recipeRecords: [HouseholdRecipeRecord] = householdGet(
            table: "household_recipes",
            query: [
                URLQueryItem(name: "select", value: "id,household_id,source_recipe_id,created_by,updated_by,version,payload,updated_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdID.uuidString)"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            accessToken: accessToken
        )
        async let planRecords: [HouseholdPlanRecord] = householdGet(
            table: "household_meal_plans",
            query: [
                URLQueryItem(name: "select", value: "id,household_id,source_plan_id,created_by,updated_by,version,payload,updated_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdID.uuidString)"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            accessToken: accessToken
        )
        async let calendarRecords: [HouseholdCalendarRecord] = householdGet(
            table: "household_calendar_meals",
            query: [
                URLQueryItem(name: "select", value: "id,household_id,meal_date,meal_type,recipe_id,assignment_id,created_by,updated_by,updated_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdID.uuidString)"),
                URLQueryItem(name: "order", value: "meal_date.asc")
            ],
            accessToken: accessToken
        )
        async let outgoingInvitations = loadOutgoingHouseholdInvitations(householdID: householdID, accessToken: accessToken)
        let (households, memberRows, recipeRows, planRows, calendarRows) = try await (householdRecords, memberRecords, recipeRecords, planRecords, calendarRecords)
        guard let household = households.first?.value else { throw SyncError.invalidResponse }
        let profileIDs = Array(Set(memberRows.map(\.userID)))
        let profiles = try await householdProfiles(ids: profileIDs, accessToken: accessToken)
        let members = memberRows.compactMap { row -> HouseholdMember? in
            guard let profile = profiles[row.userID], let role = HouseholdRole(rawValue: row.role), let joinedAt = HouseholdDateCoding.date(from: row.joinedAt) else { return nil }
            return HouseholdMember(householdID: row.householdID, userID: row.userID, role: role, joinedAt: joinedAt, profile: profile)
        }
        let receivedInvitations = try await invitations
        let sentInvitations = try await outgoingInvitations
        let combinedInvitations = Dictionary(uniqueKeysWithValues: (receivedInvitations + sentInvitations).map { ($0.id, $0) }).values.sorted { $0.createdAt > $1.createdAt }
        return HouseholdSnapshot(
            household: household,
            members: members,
            invitations: combinedInvitations,
            recipes: recipeRows.compactMap(\.value),
            plans: planRows.compactMap(\.value),
            calendarMeals: calendarRows.compactMap(\.value)
        )
    }

    func loadHouseholdInvitations(for userID: UUID, accessToken: String) async throws -> [HouseholdInvitation] {
        let records: [HouseholdInvitationRecord] = try await householdGet(
            table: "household_invitations",
            query: [
                URLQueryItem(name: "select", value: "id,household_id,inviter_id,invitee_id,status,created_at,expires_at,responded_at"),
                URLQueryItem(name: "invitee_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        guard !records.isEmpty else { return [] }
        let householdIDs = Array(Set(records.map(\.householdID)))
        let profileIDs = Array(Set(records.flatMap { [$0.inviterID, $0.inviteeID] }))
        let households: [HouseholdRecord] = try await householdGet(
            table: "households",
            query: [URLQueryItem(name: "id", value: "in.(\(householdIDs.map(\.uuidString).joined(separator: ",")))")],
            accessToken: accessToken
        )
        let profiles = try await householdProfiles(ids: profileIDs, accessToken: accessToken)
        let names = Dictionary(uniqueKeysWithValues: households.compactMap { row in row.value.map { ($0.id, $0.name) } })
        return records.compactMap { $0.value(householdName: names[$0.householdID], inviter: profiles[$0.inviterID], invitee: profiles[$0.inviteeID]) }
    }

    private func loadOutgoingHouseholdInvitations(householdID: UUID, accessToken: String) async throws -> [HouseholdInvitation] {
        let records: [HouseholdInvitationRecord] = try await householdGet(
            table: "household_invitations",
            query: [
                URLQueryItem(name: "select", value: "id,household_id,inviter_id,invitee_id,status,created_at,expires_at,responded_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdID.uuidString)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        guard !records.isEmpty else { return [] }
        let households: [HouseholdRecord] = try await householdGet(table: "households", query: [URLQueryItem(name: "id", value: "eq.\(householdID.uuidString)")], accessToken: accessToken)
        let profiles = try await householdProfiles(ids: Array(Set(records.flatMap { [$0.inviterID, $0.inviteeID] })), accessToken: accessToken)
        let name = households.first?.value?.name
        return records.compactMap { $0.value(householdName: name, inviter: profiles[$0.inviterID], invitee: profiles[$0.inviteeID]) }
    }

    func searchHouseholdProfiles(username: String, excluding userID: UUID, accessToken: String) async throws -> [UserProfile] {
        let normalized = UsernamePolicy.normalize(username)
        guard !normalized.isEmpty else { return [] }
        let records: [HouseholdProfileRecord] = try await householdGet(
            table: "profiles",
            query: [
                URLQueryItem(name: "select", value: "id,display_name,username"),
                URLQueryItem(name: "username", value: "ilike.*\(normalized)*"),
                URLQueryItem(name: "id", value: "neq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "20")
            ],
            accessToken: accessToken
        )
        return records.compactMap(\.value)
    }

    func createHousehold(name: String, accessToken: String) async throws {
        try await householdRPC("create_household", body: ["household_name": name], accessToken: accessToken)
    }

    func inviteHouseholdMember(username: String, accessToken: String) async throws {
        try await householdRPC("invite_household_member", body: ["invitee_username": UsernamePolicy.normalize(username)], accessToken: accessToken)
    }

    func respondToHouseholdInvitation(id: UUID, accept: Bool, accessToken: String) async throws {
        try await householdRPC("respond_to_household_invitation", body: InvitationResponseRPC(invitationID: id, acceptInvitation: accept), accessToken: accessToken)
    }

    func revokeHouseholdInvitation(id: UUID, accessToken: String) async throws {
        try await householdRPC("revoke_household_invitation", body: IDRPC(invitationID: id), accessToken: accessToken)
    }

    func transferHouseholdOwnership(to userID: UUID, accessToken: String) async throws {
        try await householdRPC("transfer_household_ownership", body: UserIDRPC(newOwnerID: userID), accessToken: accessToken)
    }

    func removeHouseholdMember(userID: UUID, accessToken: String) async throws {
        try await householdRPC("remove_household_member", body: MemberIDRPC(memberID: userID), accessToken: accessToken)
    }

    func leaveHousehold(accessToken: String) async throws {
        try await householdRPC("leave_household", body: EmptyHouseholdRPC(), accessToken: accessToken)
    }

    func deleteHousehold(id: UUID, accessToken: String) async throws {
        try await householdDelete(table: "households", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], accessToken: accessToken)
    }

    func renameHousehold(id: UUID, name: String, accessToken: String) async throws {
        try await householdPatch(table: "households", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], body: HouseholdNameWrite(name: name), accessToken: accessToken)
    }

    func shareRecipeToHousehold(recipeID: UUID, accessToken: String) async throws {
        try await householdRPC("share_recipe_to_household", body: RecipeIDRPC(recipeID: recipeID), accessToken: accessToken)
    }

    func sharePlanToHousehold(planID: UUID, accessToken: String) async throws {
        try await householdRPC("share_meal_plan_to_household", body: PlanIDRPC(planID: planID), accessToken: accessToken)
    }

    func saveHouseholdRecipe(_ recipe: Recipe, householdID: UUID, existingVersion: Int?, accessToken: String) async throws {
        if let existingVersion {
            try await householdPatch(
                table: "household_recipes",
                filters: [URLQueryItem(name: "id", value: "eq.\(recipe.id.uuidString)"), URLQueryItem(name: "version", value: "eq.\(existingVersion)")],
                body: HouseholdPayloadWrite(payload: recipe),
                accessToken: accessToken,
                requireChangedRow: true
            )
        } else {
            try await householdPost(table: "household_recipes", body: HouseholdRecipeWrite(id: recipe.id, householdID: householdID, payload: recipe), accessToken: accessToken)
        }
    }

    func deleteHouseholdRecipe(id: UUID, accessToken: String) async throws {
        try await householdDelete(table: "household_recipes", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], accessToken: accessToken)
    }

    func saveHouseholdPlan(_ plan: MealPlan, householdID: UUID, existingVersion: Int?, accessToken: String) async throws {
        try await householdRPC(
            "save_household_meal_plan",
            body: SaveHouseholdPlanRPC(householdID: householdID, planID: plan.id, expectedVersion: existingVersion, payload: plan),
            accessToken: accessToken
        )
    }

    func deleteHouseholdPlan(id: UUID, accessToken: String) async throws {
        try await householdDelete(table: "household_meal_plans", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], accessToken: accessToken)
    }

    func saveHouseholdCalendarMeal(_ meal: HouseholdCalendarMeal, accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/household_calendar_meals"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "household_id,meal_date,meal_type")]
        var request = householdAuthorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([HouseholdCalendarWrite(meal)])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func deleteHouseholdCalendarMeal(id: UUID, accessToken: String) async throws {
        try await householdDelete(table: "household_calendar_meals", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], accessToken: accessToken)
    }

    private func householdProfiles(ids: [UUID], accessToken: String) async throws -> [UUID: UserProfile] {
        guard !ids.isEmpty else { return [:] }
        let records: [HouseholdProfileRecord] = try await householdGet(
            table: "profiles",
            query: [
                URLQueryItem(name: "select", value: "id,display_name,username"),
                URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        return Dictionary(uniqueKeysWithValues: records.compactMap { $0.value.map { ($0.id, $0) } })
    }

    private func householdGet<Response: Decodable>(table: String, query: [URLQueryItem], accessToken: String) async throws -> Response {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let request = householdAuthorizedRequest(url: components.url!, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func householdPost<Body: Encodable>(table: String, body: Body, accessToken: String) async throws {
        let url = configuration.url.appending(path: "rest/v1/\(table)")
        var request = householdAuthorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([body])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func householdPatch<Body: Encodable>(table: String, filters: [URLQueryItem], body: Body, accessToken: String, requireChangedRow: Bool = false) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = filters
        var request = householdAuthorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requireChangedRow ? "return=representation" : "return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if requireChangedRow, (try? JSONSerialization.jsonObject(with: data) as? [Any])?.isEmpty != false {
            throw SyncError.service(message: "Someone else changed this item. Reload it and try again.")
        }
    }

    private func householdDelete(table: String, filters: [URLQueryItem], accessToken: String) async throws {
        var components = URLComponents(url: configuration.url.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = filters
        var request = householdAuthorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func householdRPC<Body: Encodable>(_ function: String, body: Body, accessToken: String) async throws {
        let url = configuration.url.appending(path: "rest/v1/rpc/\(function)")
        var request = householdAuthorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func householdAuthorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var household: Household?
    @Published private(set) var members: [HouseholdMember] = []
    @Published private(set) var invitations: [HouseholdInvitation] = []
    @Published private(set) var recipes: [HouseholdRecipe] = []
    @Published private(set) var plans: [HouseholdMealPlan] = []
    @Published private(set) var calendarMeals: [HouseholdCalendarMeal] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var client: SupabaseDataClient?
    private var session: AuthSession?
    private var cacheKey: String?

    var receivedInvitations: [HouseholdInvitation] { invitations.filter { $0.inviteeID == session?.user.id } }
    var pendingInvitationCount: Int { receivedInvitations.filter(\.canRespond).count }
    var currentUserID: UUID? { session?.user.id }
    var isOwner: Bool { household?.ownerID == session?.user.id }
    var householdRecipes: [Recipe] { recipes.map(\.recipe) }
    var householdPlans: [MealPlan] { plans.map(\.plan) }

    func activateAccount(_ session: AuthSession, client: SupabaseDataClient) async {
        guard self.session?.accessToken != session.accessToken || self.session?.user.id != session.user.id else { return }
        self.session = session
        self.client = client
        cacheKey = "household-state-v1-\(session.user.id.uuidString)"
        loadCache()
        await refresh()
    }

    func deactivateAccount() {
        client = nil
        session = nil
        cacheKey = nil
        household = nil
        members = []
        invitations = []
        recipes = []
        plans = []
        calendarMeals = []
        errorMessage = nil
    }

    func refresh() async {
        guard let client, let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await client.loadHouseholdSnapshot(for: session.user.id, accessToken: session.accessToken))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshInvitations() async {
        await refresh()
    }

    func createHousehold(name: String) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to create a household.") }
        try await client.createHousehold(name: name.trimmingCharacters(in: .whitespacesAndNewlines), accessToken: session.accessToken)
        await refresh()
    }

    func searchProfiles(_ username: String) async throws -> [UserProfile] {
        guard let client, let session else { return [] }
        return try await client.searchHouseholdProfiles(username: username, excluding: session.user.id, accessToken: session.accessToken)
            .filter { profile in
                !members.contains { $0.userID == profile.id }
                    && !invitations.contains { $0.householdID == household?.id && $0.inviteeID == profile.id && $0.canRespond }
            }
    }

    func invite(username: String) async throws { try await mutate { try await $0.inviteHouseholdMember(username: username, accessToken: $1.accessToken) } }
    func respond(to invitation: HouseholdInvitation, accept: Bool) async throws { try await mutate { try await $0.respondToHouseholdInvitation(id: invitation.id, accept: accept, accessToken: $1.accessToken) } }
    func revoke(_ invitation: HouseholdInvitation) async throws { try await mutate { try await $0.revokeHouseholdInvitation(id: invitation.id, accessToken: $1.accessToken) } }
    func rename(_ name: String) async throws {
        guard let household else { return }
        try await mutate { try await $0.renameHousehold(id: household.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), accessToken: $1.accessToken) }
    }
    func transferOwnership(to member: HouseholdMember) async throws { try await mutate { try await $0.transferHouseholdOwnership(to: member.userID, accessToken: $1.accessToken) } }
    func remove(_ member: HouseholdMember) async throws { try await mutate { try await $0.removeHouseholdMember(userID: member.userID, accessToken: $1.accessToken) } }
    func leave() async throws { try await mutate { try await $0.leaveHousehold(accessToken: $1.accessToken) } }
    func deleteHousehold() async throws {
        guard let household else { return }
        try await mutate { try await $0.deleteHousehold(id: household.id, accessToken: $1.accessToken) }
    }
    func share(recipe: Recipe) async throws { try await mutate { try await $0.shareRecipeToHousehold(recipeID: recipe.id, accessToken: $1.accessToken) } }
    func share(plan: MealPlan) async throws { try await mutate { try await $0.sharePlanToHousehold(planID: plan.id, accessToken: $1.accessToken) } }

    func save(recipe: Recipe, existingVersion: Int? = nil) async throws {
        guard let household else { throw SyncError.service(message: "Join a household first.") }
        try await mutate { try await $0.saveHouseholdRecipe(recipe, householdID: household.id, existingVersion: existingVersion, accessToken: $1.accessToken) }
    }

    func delete(recipe: HouseholdRecipe) async throws { try await mutate { try await $0.deleteHouseholdRecipe(id: recipe.id, accessToken: $1.accessToken) } }

    func save(plan: MealPlan, existingVersion: Int? = nil) async throws {
        guard let household else { throw SyncError.service(message: "Join a household first.") }
        try await mutate { try await $0.saveHouseholdPlan(plan, householdID: household.id, existingVersion: existingVersion, accessToken: $1.accessToken) }
    }

    func delete(plan: HouseholdMealPlan) async throws { try await mutate { try await $0.deleteHouseholdPlan(id: plan.id, accessToken: $1.accessToken) } }

    func schedule(recipeID: UUID, on date: Date, type: MealType, assignmentID: UUID? = nil) async throws {
        guard let household, let userID = session?.user.id else { throw SyncError.service(message: "Join a household first.") }
        let existing = calendarMeals.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.mealType == type }
        let meal = HouseholdCalendarMeal(
            id: existing?.id ?? UUID(), householdID: household.id, date: Calendar.current.startOfDay(for: date), mealType: type,
            recipeID: recipeID, assignmentID: assignmentID, createdBy: existing?.createdBy ?? userID, updatedBy: userID, updatedAt: Date()
        )
        try await mutate { try await $0.saveHouseholdCalendarMeal(meal, accessToken: $1.accessToken) }
    }

    func apply(plan: MealPlan, from startDate: Date, replaceExisting: Bool) async throws {
        guard let client, let session, let household else { throw SyncError.service(message: "Join a household first.") }
        let assignmentID = UUID()
        let start = Calendar.current.startOfDay(for: startDate)
        do {
            for planned in plan.meals {
                let dayOffset = (planned.week - 1) * 7 + max(0, planned.weekday - 1)
                guard let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: start) else { continue }
                let existing = calendarMeals.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.mealType == planned.mealType }
                if existing != nil && !replaceExisting { continue }
                let meal = HouseholdCalendarMeal(id: existing?.id ?? UUID(), householdID: household.id, date: date, mealType: planned.mealType, recipeID: planned.recipeID, assignmentID: assignmentID, createdBy: existing?.createdBy ?? session.user.id, updatedBy: session.user.id, updatedAt: Date())
                try await client.saveHouseholdCalendarMeal(meal, accessToken: session.accessToken)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func removeCalendarMeal(_ meal: HouseholdCalendarMeal) async throws { try await mutate { try await $0.deleteHouseholdCalendarMeal(id: meal.id, accessToken: $1.accessToken) } }

    func meals(on date: Date) -> [HouseholdCalendarMeal] {
        calendarMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    func recipe(_ id: UUID) -> Recipe? { recipes.first { $0.id == id }?.recipe }

    private func mutate(_ operation: (SupabaseDataClient, AuthSession) async throws -> Void) async throws {
        guard let client, let session else { throw SyncError.service(message: "Sign in to manage a household.") }
        do {
            try await operation(client, session)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func apply(_ snapshot: HouseholdSnapshot) {
        household = snapshot.household
        members = snapshot.members
        invitations = snapshot.invitations
        recipes = snapshot.recipes
        plans = snapshot.plans
        calendarMeals = snapshot.calendarMeals
        persist()
    }

    private func persist() {
        guard let cacheKey else { return }
        let snapshot = HouseholdSnapshot(household: household, members: members, invitations: invitations, recipes: recipes, plans: plans, calendarMeals: calendarMeals)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }

    private func loadCache() {
        guard let cacheKey, let data = UserDefaults.standard.data(forKey: cacheKey), let snapshot = try? JSONDecoder().decode(HouseholdSnapshot.self, from: data) else { return }
        apply(snapshot)
    }
}

private enum HouseholdDateCoding {
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let standard = ISO8601DateFormatter()
    static func date(from value: String) -> Date? { fractional.date(from: value) ?? standard.date(from: value) }
    static func string(from value: Date) -> String { fractional.string(from: value) }
    static func day(from value: Date) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: value) }
    static func dateFromDay(_ value: String) -> Date? { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f.date(from: value) }
}

private struct HouseholdRecord: Decodable {
    let id: UUID; let name: String; let ownerID: UUID; let createdAt: String; let updatedAt: String
    enum CodingKeys: String, CodingKey { case id, name; case ownerID = "owner_id"; case createdAt = "created_at"; case updatedAt = "updated_at" }
    var value: Household? { guard let created = HouseholdDateCoding.date(from: createdAt), let updated = HouseholdDateCoding.date(from: updatedAt) else { return nil }; return Household(id: id, name: name, ownerID: ownerID, createdAt: created, updatedAt: updated) }
}

private struct HouseholdMembershipRecord: Decodable {
    let householdID: UUID; let userID: UUID; let role: String; let joinedAt: String
    enum CodingKeys: String, CodingKey { case role; case householdID = "household_id"; case userID = "user_id"; case joinedAt = "joined_at" }
}

private struct HouseholdProfileRecord: Decodable {
    let id: UUID; let displayName: String; let username: String?
    enum CodingKeys: String, CodingKey { case id, username; case displayName = "display_name" }
    var value: UserProfile? { guard let username, !displayName.isEmpty else { return nil }; return UserProfile(id: id, displayName: username, username: username) }
}

private struct HouseholdInvitationRecord: Decodable {
    let id: UUID; let householdID: UUID; let inviterID: UUID; let inviteeID: UUID; let status: String; let createdAt: String; let expiresAt: String; let respondedAt: String?
    enum CodingKeys: String, CodingKey { case id, status; case householdID = "household_id"; case inviterID = "inviter_id"; case inviteeID = "invitee_id"; case createdAt = "created_at"; case expiresAt = "expires_at"; case respondedAt = "responded_at" }
    func value(householdName: String?, inviter: UserProfile?, invitee: UserProfile?) -> HouseholdInvitation? {
        guard let householdName, let inviter, let status = HouseholdInvitationStatus(rawValue: status), let createdAt = HouseholdDateCoding.date(from: createdAt), let expiresAt = HouseholdDateCoding.date(from: expiresAt) else { return nil }
        return HouseholdInvitation(id: id, householdID: householdID, householdName: householdName, inviter: inviter, invitee: invitee, inviteeID: inviteeID, status: status, createdAt: createdAt, expiresAt: expiresAt, respondedAt: respondedAt.flatMap(HouseholdDateCoding.date))
    }
}

private struct HouseholdRecipeRecord: Decodable {
    let id: UUID; let householdID: UUID; let sourceRecipeID: UUID?; let createdBy: UUID?; let updatedBy: UUID?; let version: Int; let payload: Recipe; let updatedAt: String
    enum CodingKeys: String, CodingKey { case id, version, payload; case householdID = "household_id"; case sourceRecipeID = "source_recipe_id"; case createdBy = "created_by"; case updatedBy = "updated_by"; case updatedAt = "updated_at" }
    var value: HouseholdRecipe? { guard let date = HouseholdDateCoding.date(from: updatedAt) else { return nil }; return HouseholdRecipe(householdID: householdID, sourceRecipeID: sourceRecipeID, createdBy: createdBy, updatedBy: updatedBy, version: version, recipe: payload, updatedAt: date) }
}

private struct HouseholdPlanRecord: Decodable {
    let id: UUID; let householdID: UUID; let sourcePlanID: UUID?; let createdBy: UUID?; let updatedBy: UUID?; let version: Int; let payload: MealPlan; let updatedAt: String
    enum CodingKeys: String, CodingKey { case id, version, payload; case householdID = "household_id"; case sourcePlanID = "source_plan_id"; case createdBy = "created_by"; case updatedBy = "updated_by"; case updatedAt = "updated_at" }
    var value: HouseholdMealPlan? { guard let date = HouseholdDateCoding.date(from: updatedAt) else { return nil }; return HouseholdMealPlan(householdID: householdID, sourcePlanID: sourcePlanID, createdBy: createdBy, updatedBy: updatedBy, version: version, plan: payload, updatedAt: date) }
}

private struct HouseholdCalendarRecord: Decodable {
    let id: UUID; let householdID: UUID; let mealDate: String; let mealType: String; let recipeID: UUID; let assignmentID: UUID?; let createdBy: UUID?; let updatedBy: UUID?; let updatedAt: String
    enum CodingKeys: String, CodingKey { case id; case householdID = "household_id"; case mealDate = "meal_date"; case mealType = "meal_type"; case recipeID = "recipe_id"; case assignmentID = "assignment_id"; case createdBy = "created_by"; case updatedBy = "updated_by"; case updatedAt = "updated_at" }
    var value: HouseholdCalendarMeal? { guard let date = HouseholdDateCoding.dateFromDay(mealDate), let type = MealType(rawValue: mealType), let updated = HouseholdDateCoding.date(from: updatedAt) else { return nil }; return HouseholdCalendarMeal(id: id, householdID: householdID, date: date, mealType: type, recipeID: recipeID, assignmentID: assignmentID, createdBy: createdBy, updatedBy: updatedBy, updatedAt: updated) }
}

private struct HouseholdRecipeWrite: Encodable { let id: UUID; let householdID: UUID; let payload: Recipe; enum CodingKeys: String, CodingKey { case id, payload; case householdID = "household_id" } }
private struct HouseholdPayloadWrite<Payload: Encodable>: Encodable { let payload: Payload }
private struct HouseholdNameWrite: Encodable { let name: String }
private struct HouseholdCalendarWrite: Encodable {
    let id: UUID; let householdID: UUID; let mealDate: String; let mealType: String; let recipeID: UUID; let assignmentID: UUID?; let createdBy: UUID?; let updatedBy: UUID?
    init(_ meal: HouseholdCalendarMeal) { id = meal.id; householdID = meal.householdID; mealDate = HouseholdDateCoding.day(from: meal.date); mealType = meal.mealType.rawValue; recipeID = meal.recipeID; assignmentID = meal.assignmentID; createdBy = meal.createdBy; updatedBy = meal.updatedBy }
    enum CodingKeys: String, CodingKey { case id; case householdID = "household_id"; case mealDate = "meal_date"; case mealType = "meal_type"; case recipeID = "recipe_id"; case assignmentID = "assignment_id"; case createdBy = "created_by"; case updatedBy = "updated_by" }
}
private struct InvitationResponseRPC: Encodable { let invitationID: UUID; let acceptInvitation: Bool; enum CodingKeys: String, CodingKey { case invitationID = "invitation_id"; case acceptInvitation = "accept_invitation" } }
private struct IDRPC: Encodable { let invitationID: UUID; enum CodingKeys: String, CodingKey { case invitationID = "invitation_id" } }
private struct UserIDRPC: Encodable { let newOwnerID: UUID; enum CodingKeys: String, CodingKey { case newOwnerID = "new_owner_id" } }
private struct MemberIDRPC: Encodable { let memberID: UUID; enum CodingKeys: String, CodingKey { case memberID = "member_id" } }
private struct RecipeIDRPC: Encodable { let recipeID: UUID; enum CodingKeys: String, CodingKey { case recipeID = "recipe_id" } }
private struct PlanIDRPC: Encodable { let planID: UUID; enum CodingKeys: String, CodingKey { case planID = "plan_id" } }
private struct SaveHouseholdPlanRPC: Encodable { let householdID: UUID; let planID: UUID; let expectedVersion: Int?; let payload: MealPlan; enum CodingKeys: String, CodingKey { case householdID = "p_household_id"; case planID = "p_plan_id"; case expectedVersion = "p_expected_version"; case payload = "p_payload" } }
private struct EmptyHouseholdRPC: Encodable {}
