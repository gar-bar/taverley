import Foundation
import Testing
@testable import RecipeApp

@Suite("Shared feed")
struct FeedFeatureTests {
    private let authorID = UUID(uuidString: "C4C505D4-A77F-43E1-B6A0-C2F837110BA2")!

    @Test func composerRequiresTrimmedTitleAndDetails() {
        let valid = FeedPost(authorID: authorID, title: " Dinner ", body: " Details ", recipeID: nil, photoPaths: [])
        let missingTitle = FeedPost(authorID: authorID, title: "  ", body: "Details", recipeID: nil, photoPaths: [])
        let missingDetails = FeedPost(authorID: authorID, title: "Dinner", body: "\n", recipeID: nil, photoPaths: [])

        #expect(valid.isValidForPublishing)
        #expect(!missingTitle.isValidForPublishing)
        #expect(!missingDetails.isValidForPublishing)
    }

    @Test func postRejectsMoreThanFourPhotos() {
        let four = FeedPost(authorID: authorID, title: "Title", body: "Body", recipeID: nil, photoPaths: ["1", "2", "3", "4"])
        let five = FeedPost(authorID: authorID, title: "Title", body: "Body", recipeID: nil, photoPaths: ["1", "2", "3", "4", "5"])

        #expect(four.isValidForPublishing)
        #expect(!five.isValidForPublishing)
    }

    @Test func usernameNormalizationAndValidation() {
        #expect(UsernamePolicy.normalize(" @Elisa.Kazan ") == "elisa.kazan")
        #expect(UsernamePolicy.isValid("cook_01"))
        #expect(!UsernamePolicy.isValid("ab"))
        #expect(!UsernamePolicy.isValid("not valid"))
        #expect(UsernamePolicy.isValid("UPPERCASE"))
        #expect(UsernamePolicy.normalize("UPPERCASE") == "uppercase")
    }

    @Test func passwordPolicyRequiresTwelveCharactersNumberAndSymbol() {
        #expect(PasswordPolicy.isValid("long-password1"))
        #expect(!PasswordPolicy.isValid("short-p1!"))
        #expect(!PasswordPolicy.isValid("long-password!"))
        #expect(!PasswordPolicy.isValid("longpassword12"))
    }

    @Test func feedSearchMatchesEverySupportedField() {
        let recipe = Recipe(
            title: "Lemon Pasta",
            summary: "Bright and quick",
            author: "Elisa",
            servings: 2,
            tags: [],
            ingredients: [Ingredient(name: "spaghetti", quantity: 200, unit: "g")],
            steps: [],
            nutrition: []
        )
        let item = FeedItem(
            post: FeedPost(authorID: authorID, title: "Weeknight favorite", body: "Ready in twenty minutes", recipeID: recipe.id, photoPaths: []),
            author: UserProfile(id: authorID, displayName: "Elisa Kazan", username: "elisak"),
            recipe: recipe
        )

        for query in ["Elisa", "@elisak", "favorite", "twenty", "Lemon", "spaghetti", "200 g"] {
            #expect(item.matches(query), "Expected a match for \(query)")
        }
        #expect(!item.matches("chocolate"))
    }

    @Test func newestFirstOrdering() {
        let profile = UserProfile(id: authorID, displayName: "Cook", username: "cook")
        let older = FeedItem(post: FeedPost(authorID: authorID, title: "Older", body: "Body", recipeID: nil, photoPaths: [], createdAt: Date(timeIntervalSince1970: 1)), author: profile, recipe: nil)
        let newer = FeedItem(post: FeedPost(authorID: authorID, title: "Newer", body: "Body", recipeID: nil, photoPaths: [], createdAt: Date(timeIntervalSince1970: 2)), author: profile, recipe: nil)

        #expect([older, newer].sorted { $0.post.createdAt > $1.post.createdAt }.map(\.post.title) == ["Newer", "Older"])
    }

    @Test func socialSearchNormalizesAtPrefixWhitespaceAndCase() {
        #expect(SocialSearchPolicy.normalize("  @Elisa.Kazan  ") == "elisa.kazan")
        #expect(SocialSearchPolicy.normalize("   ").isEmpty)
    }

    @Test func usersCannotFollowThemselves() {
        #expect(!SocialFollowPolicy.canFollow(currentUserID: authorID, profileID: authorID))
        #expect(SocialFollowPolicy.canFollow(currentUserID: authorID, profileID: UUID()))
    }

    @Test func optimisticFollowTransitionUpdatesFollowerCount() {
        let unfollowed = ProfileRelationship(isFollowing: false, followerCount: 3, followingCount: 7)
        let followed = unfollowed.togglingFollow()
        #expect(followed.isFollowing)
        #expect(followed.followerCount == 4)
        #expect(followed.followingCount == 7)
        #expect(followed.togglingFollow() == unfollowed)
    }

    @Test func privateFollowRequestDoesNotIncreaseFollowerCountUntilApproved() {
        let relationship = ProfileRelationship(isFollowing: false, followerCount: 3, followingCount: 7)
        let requested = relationship.applyingFollowResult(isFollowing: false, isRequested: true)
        #expect(requested.followerCount == 3)
        #expect(requested.isRequested)
        let approved = requested.applyingFollowResult(isFollowing: true, isRequested: false)
        #expect(approved.followerCount == 4)
        #expect(approved.isFollowing)
        #expect(!approved.isRequested)
    }

    @Test func socialPaginationDeduplicatesExistingPeople() {
        let first = SocialProfileSummary(
            profile: UserProfile(id: authorID, displayName: "Cook", username: "cook"),
            relationship: ProfileRelationship(isFollowing: false, followerCount: 0, followingCount: 0)
        )
        let second = SocialProfileSummary(
            profile: UserProfile(id: UUID(), displayName: "Baker", username: "baker"),
            relationship: ProfileRelationship(isFollowing: true, followerCount: 1, followingCount: 2)
        )
        #expect(SocialPagePolicy.merging([first], with: [first, second]).map(\.id) == [first.id, second.id])
    }

    @Test func sharedRecipesAreDeduplicatedInPostOrder() {
        let firstRecipe = UUID()
        let secondRecipe = UUID()
        let posts = [
            FeedPost(authorID: authorID, title: "One", body: "Body", recipeID: firstRecipe, photoPaths: []),
            FeedPost(authorID: authorID, title: "Again", body: "Body", recipeID: firstRecipe, photoPaths: []),
            FeedPost(authorID: authorID, title: "Two", body: "Body", recipeID: secondRecipe, photoPaths: [])
        ]
        #expect(SharedRecipePolicy.recipeIDs(from: posts) == [firstRecipe, secondRecipe])
    }

    @Test func postRoundTripWithoutRecipeOrPhotos() throws {
        let post = FeedPost(authorID: authorID, title: "Title", body: "Body", recipeID: nil, photoPaths: [])
        let decoded = try JSONDecoder().decode(FeedPost.self, from: JSONEncoder().encode(post))

        #expect(decoded == post)
        #expect(decoded.recipeID == nil)
        #expect(decoded.photoPaths.isEmpty)
    }

    @Test func persistedSessionKeepsAbsoluteExpiryAcrossRelaunch() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let session = AuthSession(
            accessToken: "access", refreshToken: "refresh", expiresAt: expiry,
            user: AuthUser(id: authorID, email: "cook@example.com")
        )

        let encoded = try JSONEncoder().encode(session)
        let stored = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(stored["stored_expires_at"] as? Double == expiry.timeIntervalSince1970)
        #expect(stored["expires_in"] == nil)
        #expect(try JSONDecoder().decode(AuthSession.self, from: encoded).expiresAt == expiry)
    }

    @Test func authResponseUsesServerAbsoluteExpiry() throws {
        let json = #"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"expires_at":1800000000,"user":{"id":"C4C505D4-A77F-43E1-B6A0-C2F837110BA2","email":"cook@example.com"}}"#
        let decoded = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))

        #expect(decoded.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func recipeNutritionFactsRoundTrip() throws {
        let facts = [
            NutritionFact(name: "Calories", amount: 420, unit: "kcal"),
            NutritionFact(name: "Protein", amount: 24, unit: "g")
        ]
        let recipe = Recipe(title: "Protein Pasta", summary: "", author: "Cook", servings: 2, tags: [], ingredients: [], steps: [], nutrition: facts)
        let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))

        #expect(decoded.nutrition == facts)
        #expect(decoded.calories == 420)
    }

    @Test func legacyRecipeDecodesWithoutTimeFields() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","title":"Soup","summary":"","author":"Cook","servings":2,"tags":[],"ingredients":[],"steps":[],"nutrition":[],"notes":"","createdAt":0}"#
        let decoded = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))

        #expect(decoded.prepTimeMinutes == nil)
        #expect(decoded.cookTimeMinutes == nil)
        #expect(decoded.totalTimeMinutes == nil)
    }

    @Test func recipeTotalTimeCombinesAvailableParts() {
        var recipe = Recipe(title: "Pasta", summary: "", author: "Cook", servings: 2, tags: [], ingredients: [], steps: [], nutrition: [])
        recipe.prepTimeMinutes = 15
        #expect(recipe.totalTimeMinutes == 15)
        recipe.cookTimeMinutes = 20
        #expect(recipe.totalTimeMinutes == 35)
    }

    @Test func favouriteFiltersAreExclusiveAndStartWithRecipes() {
        let selected = FavouriteKind.recipes

        #expect(selected == .recipes)
        #expect(FavouriteKind.allCases == [.recipes, .posts])
    }

    @Test func favouritePageCarriesIndependentPaginationMetadata() {
        let recipe = Recipe(title: "Saved", summary: "", author: "Cook", servings: 1, tags: [], ingredients: [], steps: [], nutrition: [])
        let page = FavouritePage(items: [recipe], nextOffset: 25, totalCount: 26)

        #expect(page.items.map(\.id) == [recipe.id])
        #expect(page.nextOffset == 25)
        #expect(page.totalCount == 26)
    }

    @Test func householdInvitationExpiresAndCannotBeAccepted() {
        let inviter = UserProfile(id: authorID, displayName: "Owner", username: "owner")
        let invitation = HouseholdInvitation(
            id: UUID(), householdID: UUID(), householdName: "Test Kitchen", inviter: inviter, invitee: nil,
            inviteeID: UUID(), status: .pending, createdAt: Date(timeIntervalSince1970: 1),
            expiresAt: Date(timeIntervalSince1970: 2), respondedAt: nil
        )
        #expect(invitation.isExpired)
        #expect(!invitation.canRespond)
    }

    @Test func householdRecipeCopyIsIndependent() {
        let original = Recipe(title: "Soup", summary: "Original", author: "Cook", servings: 2, tags: [], ingredients: [], steps: [], nutrition: [])
        let copiedID = UUID()
        var copy = HouseholdSharingPolicy.copy(original, id: copiedID)
        copy.title = "Household Soup"
        #expect(copy.id == copiedID)
        #expect(original.title == "Soup")
        #expect(copy.title == "Household Soup")
    }

    @Test func householdPlanRemapsRecipes() {
        let originalRecipeID = UUID()
        let sharedRecipeID = UUID()
        let plan = MealPlan(name: "Week", tags: [], weekCount: 1, meals: [PlanMeal(week: 1, weekday: 1, mealType: .dinner, recipeID: originalRecipeID)])
        let copy = HouseholdSharingPolicy.copy(plan, recipeIDs: [originalRecipeID: sharedRecipeID])
        #expect(copy.meals.first?.recipeID == sharedRecipeID)
        #expect(plan.meals.first?.recipeID == originalRecipeID)
    }

    @Test func householdCalendarReplacesOnlyMatchingSlot() {
        let householdID = UUID()
        let userID = UUID()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let breakfast = HouseholdCalendarMeal(id: UUID(), householdID: householdID, date: day, mealType: .breakfast, recipeID: UUID(), createdBy: userID, updatedBy: userID, updatedAt: day)
        let dinner = HouseholdCalendarMeal(id: UUID(), householdID: householdID, date: day, mealType: .dinner, recipeID: UUID(), createdBy: userID, updatedBy: userID, updatedAt: day)
        let replacement = HouseholdCalendarMeal(id: UUID(), householdID: householdID, date: day, mealType: .dinner, recipeID: UUID(), createdBy: userID, updatedBy: userID, updatedAt: day)
        let result = HouseholdCalendarPolicy.upserting(replacement, into: [breakfast, dinner])
        #expect(result.count == 2)
        #expect(result.contains { $0.id == breakfast.id })
        #expect(result.contains { $0.id == replacement.id })
        #expect(!result.contains { $0.id == dinner.id })
    }

    @Test func householdOptimisticVersionMustMatch() {
        #expect(HouseholdConflictPolicy.isCurrent(localVersion: 3, remoteVersion: 3))
        #expect(!HouseholdConflictPolicy.isCurrent(localVersion: 2, remoteVersion: 3))
    }
}
