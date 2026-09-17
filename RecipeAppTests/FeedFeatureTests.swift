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
}
