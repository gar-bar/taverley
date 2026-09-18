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

    @Test func postRoundTripWithoutRecipeOrPhotos() throws {
        let post = FeedPost(authorID: authorID, title: "Title", body: "Body", recipeID: nil, photoPaths: [])
        let decoded = try JSONDecoder().decode(FeedPost.self, from: JSONEncoder().encode(post))

        #expect(decoded == post)
        #expect(decoded.recipeID == nil)
        #expect(decoded.photoPaths.isEmpty)
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
