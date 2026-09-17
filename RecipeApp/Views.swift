import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct RootView: View {
    @State private var tab = 0
    var body: some View {
        ZStack(alignment: .bottom) {
            Group { switch tab { case 0: FeedView(); case 1: RecipeLibraryView(); case 2: MealPlanListView(); case 3: CalendarView(); default: ProfileView(onBack: { tab = 1 }) } }
            FigmaBottomBar(selected: $tab).padding(.bottom, 8)
        }.preferredColorScheme(.dark)
    }
}

struct FigmaBottomBar: View {
    @Binding var selected: Int
    private let assetNames = ["", "FigmaNavDocument", "FigmaNavFolder", "FigmaNavCalendar", "FigmaNavProfile"]
    var body: some View { HStack(spacing: 20) { ForEach(0..<5, id: \.self) { index in Button { selected = index } label: { ZStack { if selected == index { RoundedRectangle(cornerRadius: 12).fill(AppTheme.input).frame(width: 45, height: 45) }; if index == 0 { Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(AppTheme.text) } else { Image(assetNames[index]).resizable().renderingMode(.original).scaledToFit().frame(width: 25, height: 25) } }.frame(width: 50, height: 50) }.buttonStyle(.plain).accessibilityLabel(["My Feed", "My Recipes", "My Meal Plans", "Meal Planning", "My Profile"][index]) } }.padding(.horizontal, 21).frame(height: 50).background(AppTheme.surface.opacity(0.96)).overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.input, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.3), radius: 12, y: 5) }
}

struct PlaceholderView: View { let title: String; let detail: String; var body: some View { ZStack { AppTheme.background.ignoresSafeArea(); ContentUnavailableView(title, systemImage: "fork.knife", description: Text(detail)) } } }

struct AuthenticationGate: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var feedStore: FeedStore

    var body: some View {
        Group {
            if authentication.isRestoring {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    ProgressView().tint(AppTheme.primary)
                }
            } else if authentication.isSkippingForNow {
                RootView()
                    .onAppear { feedStore.deactivateAccount() }
            } else if let session = authentication.session, let dataClient = authentication.dataClient {
                RootView()
                    .task(id: session.user.id) {
                        await store.activateAccount(session, client: dataClient)
                        await feedStore.activateAccount(session, client: dataClient)
                    }
            } else {
                EmailCodeSignInView()
                    .onAppear {
                        store.deactivateAccount()
                        feedStore.deactivateAccount()
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EmailCodeSignInView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 100)

                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(AppTheme.primary)

                    Text("Welcome to Taverley")
                        .font(.custom("Plus Jakarta Sans", size: 31).weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .padding(.top, 24)

                    Text("Sign in to keep your recipes and meal plans private, safe, and available on every device.")
                        .font(.custom("Inter", size: 16))
                        .foregroundStyle(AppTheme.label)
                        .lineSpacing(3)
                        .padding(.top, 10)

                    Text("Email address")
                        .font(.custom("Inter", size: 15).weight(.medium))
                        .foregroundStyle(AppTheme.text)
                        .padding(.top, 30)

                    TextField("you@example.com", text: $email)
                        .figmaInput()
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .padding(.top, 8)

                    Text("Password")
                        .font(.custom("Inter", size: 15).weight(.medium))
                        .foregroundStyle(AppTheme.text)
                        .padding(.top, 18)

                    SecureField("Password", text: $password)
                        .figmaInput()
                        .textContentType(.password)
                        .padding(.top, 8)

                    Button(action: signIn) {
                        buttonLabel("Sign in")
                    }
                    .disabled(!isValidEmail || password.isEmpty || isSubmitting)
                    .padding(.top, 14)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.custom("Inter", size: 14))
                            .foregroundStyle(.red)
                            .padding(.top, 16)
                    }

                    Button("Skip for now") {
                        authentication.isSkippingForNow = true
                    }
                    .font(.custom("Inter", size: 16).weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                    Text("Test accounts can be created manually in Supabase. Password reset and Apple sign-in will be added later.")
                        .font(.custom("Inter", size: 13))
                        .foregroundStyle(AppTheme.label)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private func buttonLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            if isSubmitting { ProgressView().tint(.black) }
            Text(title)
        }
        .font(.custom("Inter", size: 16).weight(.bold))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(AppTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(isSubmitting ? 0.72 : 1)
    }

    private func signIn() {
        Task {
            isSubmitting = true
            errorMessage = nil
            do {
                email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                try await authentication.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

}

struct ProfileView: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var authentication: AuthenticationStore
    let onBack: () -> Void
    @State private var avatarItem: PhotosPickerItem?
    @AppStorage("profileAvatarImageData") private var avatarImageData: Data?
    @State private var showAccountOptions = false
    @State private var selectedPostID: UUID?

    private var featuredRecipes: [Recipe] { Array(store.recipes.prefix(8)) }
    private var authoredPosts: [FeedItem] {
        guard let userID = feedStore.currentProfile?.id ?? feedStore.currentUserID else { return [] }
        return feedStore.items.filter { $0.post.authorID == userID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(AppTheme.text)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button { showAccountOptions = true } label: {
                            Image(systemName: "gearshape")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(AppTheme.text)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 20)

                    HStack(alignment: .center, spacing: 28) {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                avatarImage
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                                Image(systemName: "pencil")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                                    .frame(width: 30, height: 30)
                                    .background(AppTheme.input)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppTheme.background, lineWidth: 3))
                                    .offset(x: 5, y: 5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change profile image")

                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feedStore.currentProfile?.displayName ?? "Garnet")
                                    .font(.custom("Plus Jakarta Sans", size: 34).weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                                if let username = feedStore.currentProfile?.username {
                                    Text("@\(username)")
                                        .font(.custom("Inter", size: 14))
                                        .foregroundStyle(AppTheme.label)
                                }
                            }

                            HStack(spacing: 34) {
                                ProfileStat(title: "Following", value: "0")
                                ProfileStat(title: "Followers", value: "0")
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("Recipes")
                            .font(.custom("Plus Jakarta Sans", size: 30).weight(.bold))
                        Text("\(store.recipes.count)")
                            .font(.custom("Inter", size: 28))
                            .foregroundStyle(AppTheme.label)
                    }
                    .foregroundStyle(AppTheme.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 44)

                    if featuredRecipes.isEmpty {
                        Text("Your recipes will appear here.")
                            .font(.custom("Inter", size: 16))
                            .foregroundStyle(AppTheme.label)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(featuredRecipes) { recipe in
                                    NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                        ProfileRecipeCard(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                        }
                        .scrollIndicators(.hidden)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("Posts")
                            .font(.custom("Plus Jakarta Sans", size: 30).weight(.bold))
                        Text("\(authoredPosts.count)")
                            .font(.custom("Inter", size: 28))
                            .foregroundStyle(AppTheme.label)
                    }
                    .foregroundStyle(AppTheme.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    if authoredPosts.isEmpty {
                        Text("Posts you share will appear here.")
                            .font(.custom("Inter", size: 16))
                            .foregroundStyle(AppTheme.label)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .padding(.bottom, 112)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(authoredPosts) { post in
                                FeedPostCard(item: post) {
                                    selectedPostID = post.id
                                }
                                Divider()
                                    .overlay(AppTheme.border)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 112)
                    }
                    }
                }
                .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPostID) { postID in
            PostDetailView(postID: postID)
        }
        }
        .confirmationDialog("Account", isPresented: $showAccountOptions, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                authentication.signOut()
            }
        } message: {
            Text("You can sign in with a different test account after signing out.")
        }
        .task(id: avatarItem) {
            guard let avatarItem else { return }
            avatarImageData = try? await avatarItem.loadTransferable(type: Data.self)
        }
    }

    @ViewBuilder private var avatarImage: some View {
        if let avatarImageData, let image = UIImage(data: avatarImageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image("FigmaRecipe3").resizable().scaledToFill()
        }
    }
}

private struct ProfileStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.custom("Inter", size: 16).weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text(value)
                .font(.custom("Inter", size: 23))
                .foregroundStyle(AppTheme.text)
        }
    }
}

private struct ProfileRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            recipeImage
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.custom("Plus Jakarta Sans", size: 19).weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Text(recipe.author)
                    .font(.custom("Inter", size: 14))
                    .foregroundStyle(AppTheme.label)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(recipe.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.custom("Inter", size: 12).weight(.medium))
                            .foregroundStyle(AppTheme.text)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(AppTheme.primary.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(width: 162, alignment: .leading)
        }
        .padding(10)
        .frame(width: 278, alignment: .leading)
        .background(AppTheme.background)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var recipeImage: some View {
        if let data = recipe.imageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(recipe.title == "Apple Pie" ? "FigmaRecipe2" : "FigmaRecipe3").resizable().scaledToFill()
        }
    }
}


struct LibraryHeader: View {
    let title: String

    var body: some View {
        ZStack {
            Text(title).font(.custom("Plus Jakarta Sans", size: 28).weight(.bold)).foregroundStyle(AppTheme.text)
            HStack { Spacer(); Image(systemName: "gearshape").foregroundStyle(AppTheme.text) }
        }
        .frame(height: 54)
    }
}

struct MultiSelectFilterMenu: View {
    let title: String
    @Binding var selections: Set<String>
    let options: [String]
    @State private var isExpanded = false

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 6) {
                Text(selections.isEmpty ? title : "\(title) (\(selections.count))")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.custom("Inter", size: 16).weight(.medium))
            .foregroundStyle(selections.isEmpty ? AppTheme.label : AppTheme.primary)
            .padding(.horizontal, 12)
            .background(AppTheme.input)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            dropdownPanel
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.clear)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var dropdownPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !selections.isEmpty {
                Button { selections.removeAll() } label: {
                    Label("Clear selection", systemImage: "xmark.circle").foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 40)
                }
                .buttonStyle(.plain)
                Divider().overlay(AppTheme.border)
            }
            ForEach(options, id: \.self) { option in
                Button { toggle(option) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selections.contains(option) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selections.contains(option) ? AppTheme.primary : AppTheme.label)
                        Text(option).foregroundStyle(AppTheme.text)
                        Spacer()
                    }
                    .font(.custom("Inter", size: 15).weight(.medium))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(selections.contains(option) ? AppTheme.input.opacity(0.8) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 220, alignment: .leading)
        .background(AppTheme.surface.opacity(0.98))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.38), radius: 14, y: 8)
    }

    private func toggle(_ option: String) {
        if selections.contains(option) { selections.remove(option) }
        else { selections.insert(option) }
    }
}

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: MealStore
    @State private var query = ""; @State private var selectedTags: Set<String> = []; @State private var selectedAuthors: Set<String> = []; @State private var showCreate = false
    private var tags: [String] { Array(Set(store.recipes.flatMap(\.tags))).sorted() }
    private var authors: [String] { Array(Set(store.recipes.map(\.author))).sorted() }
    private var filtered: [Recipe] { store.recipes.filter { recipe in (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) } || recipe.author.localizedCaseInsensitiveContains(query)) && (selectedTags.isEmpty || !selectedTags.isDisjoint(with: Set(recipe.tags))) && (selectedAuthors.isEmpty || selectedAuthors.contains(recipe.author)) } }
    var body: some View { NavigationStack { ZStack(alignment: .bottomTrailing) { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(alignment: .leading, spacing: 10) { LibraryHeader(title: "My Recipes").padding(.horizontal, 16); HStack { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query) }.figmaInput().padding(.horizontal, 16); HStack(spacing: 10) { MultiSelectFilterMenu(title: "Author", selections: $selectedAuthors, options: authors); MultiSelectFilterMenu(title: "Label", selections: $selectedTags, options: tags) }.padding(.horizontal, 16).zIndex(1); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(filtered) { recipe in NavigationLink { RecipeDetailView(recipe: recipe) } label: { RecipeCard(recipe: recipe) } } }.padding(.horizontal, 16).padding(.bottom, 80) } }.scrollIndicators(.hidden); Button { showCreate = true } label: { Label("Create Recipe", systemImage: "plus").font(.subheadline.weight(.bold)).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()).shadow(radius: 8) }.padding(.trailing, 20).padding(.bottom, 90) }.navigationBarHidden(true).sheet(isPresented: $showCreate) { RecipeEditor() } } }
}

struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let data = recipe.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(recipe.title == "Apple Pie" ? "FigmaRecipe2" : "FigmaRecipe3").resizable().scaledToFill() }
                }.frame(height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                Text(recipe.title).font(.headline).foregroundStyle(AppTheme.text).lineLimit(1)
                Text("@\(recipe.author)").font(.caption).foregroundStyle(AppTheme.label)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject private var store: MealStore; @Environment(\.dismiss) private var dismiss; let recipe: Recipe; @State private var scale = 1.0; @State private var ingredientsOpen = true; @State private var stepsOpen = false; @State private var nutritionOpen = false
    var body: some View { ZStack { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing: 0) {
        ZStack(alignment: .top) {
            Group {
                if let data = recipe.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                else { Image("FigmaHero").resizable().scaledToFill() }
            }.frame(height: 180).clipped().overlay(AppTheme.background.opacity(0.28))
            HStack { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text).frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle()) }; Spacer(); Button { } label: { Image(systemName: "star") }; Button { } label: { Image(systemName: "square.and.arrow.up") } }.font(.body.weight(.semibold)).foregroundStyle(AppTheme.text).padding(.horizontal, 16).padding(.top, 14)
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) { Circle().fill(AppTheme.primary.opacity(0.35)).frame(width: 25, height: 25).overlay(Image(systemName: "person.fill").font(.caption)); VStack(alignment: .leading, spacing: 0) { Text(recipe.author).font(.custom("Inter", size: 12).weight(.medium)); Text("@\(recipe.author.lowercased())").font(.custom("Inter", size: 10)).foregroundStyle(AppTheme.label) }; Spacer(); VStack(alignment: .trailing, spacing: 2) { Label("4.8 (30)", systemImage: "star.fill").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.primary); Text("30 Minutes").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label) } }
            Text(recipe.title).font(.custom("Plus Jakarta Sans", size: 28).weight(.bold)).foregroundStyle(AppTheme.text)
            Text(recipe.summary).font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            Accordion(title: "Ingredients", isOpen: $ingredientsOpen) { Picker("Scale", selection: $scale) { Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }.pickerStyle(.segmented); ForEach(recipe.ingredients) { item in Text("• \((item.quantity * scale).formatted(.number.precision(.fractionLength(0...2)))) \(item.unit) \(item.name)").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading) } }
            Accordion(title: "Instructions", isOpen: $stepsOpen) { ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in Text("\(index + 1). \(step.text)").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4) } }
            Accordion(title: "Nutrition Facts", isOpen: $nutritionOpen) { ForEach(recipe.nutrition) { fact in HStack { Text(fact.name); Spacer(); Text("\(fact.amount.formatted()) \(fact.unit)") }.font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text) } }
        }.padding(16).padding(.bottom, 28).background(AppTheme.background).clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)).offset(y: -15)
    } }.scrollIndicators(.hidden) }.toolbar(.hidden, for: .navigationBar) }
}

struct Accordion<Content: View>: View { let title: String; @Binding var isOpen: Bool; @ViewBuilder let content: Content; var body: some View { SurfaceCard { VStack(alignment: .leading, spacing: 12) { Button { withAnimation { isOpen.toggle() } } label: { HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); Image(systemName: isOpen ? "chevron.up" : "chevron.down") }.foregroundStyle(AppTheme.text) }; if isOpen { content } } } } }

struct RecipeEditor: View {
    @EnvironmentObject private var store: MealStore; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var summary = ""; @State private var author = ""; @State private var servings = 4; @State private var tags = ""; @State private var ingredients = [Ingredient(name: "", quantity: 1, unit: "cups")]; @State private var steps = [RecipeStep(text: "")]; @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        recipeCoverPicker
                        recipeForm
                            .padding(16)
                            .background(AppTheme.background)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                            .offset(y: -15)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            imageData = try? await photoItem.loadTransferable(type: Data.self)
        }
    }

    private var recipeCoverPicker: some View {
        ZStack(alignment: .topLeading) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.35)) }
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    Label(imageData == nil ? "Add cover image" : "Change image", systemImage: "photo")
                        .font(.custom("Inter", size: 12).weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(AppTheme.input.opacity(0.96)).foregroundStyle(AppTheme.text)
                        .clipShape(Capsule()).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text).frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle()) }
                .padding(14)
        }
    }

    private var recipeForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) { Circle().fill(AppTheme.primary.opacity(0.35)).frame(width: 25, height: 25); VStack(alignment: .leading, spacing: 0) { Text(author.isEmpty ? "Author" : author).font(.custom("Inter", size: 12)); Text("@author").font(.custom("Inter", size: 10)).foregroundStyle(AppTheme.label) } }
            TextField("Add Title", text: $title).figmaInput().padding(.bottom, 8)
            TextField("Add Description", text: $summary, axis: .vertical).lineLimit(3...5).figmaInput().padding(.bottom, 8)
            HStack { Text("Serves \(servings)").foregroundStyle(AppTheme.label); Stepper("", value: $servings, in: 1...30).labelsHidden(); TextField("Tags", text: $tags).figmaInput() }.padding(.bottom, 8)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Ingredients").font(.custom("Plus Jakarta Sans", size: 22).weight(.semibold))
                    HStack(spacing: 8) { Text("Ingredient").frame(maxWidth: .infinity, alignment: .leading); Text("Quantity").frame(maxWidth: .infinity, alignment: .leading); Text("Measure").frame(maxWidth: .infinity, alignment: .leading) }.font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                    ForEach($ingredients) { $ingredient in IngredientInputRow(ingredient: $ingredient) }
                    Button("Add Ingredient", systemImage: "plus") { ingredients.append(Ingredient(name: "", quantity: 1, unit: "")) }.buttonStyle(.bordered).tint(AppTheme.primary)
                }
            }
            SurfaceCard { VStack(alignment: .leading, spacing: 9) { Text("Instructions").font(.custom("Plus Jakarta Sans", size: 22).weight(.semibold)); ForEach($steps) { $step in TextField("Add Instructions", text: $step.text, axis: .vertical).lineLimit(2...4).figmaInput() }; Button("Add Step", systemImage: "plus") { steps.append(RecipeStep(text: "")) }.buttonStyle(.bordered).tint(AppTheme.primary) } }
            PrimaryButton(title: "Save Recipe") { saveRecipe() }
        }
    }

    private func saveRecipe() {
        let recipe = Recipe(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, author: author.isEmpty ? "Me" : author, servings: servings, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, ingredients: ingredients.filter { !$0.name.isEmpty }, steps: steps.filter { !$0.text.isEmpty }, nutrition: [], imageData: imageData)
        guard !recipe.title.isEmpty, !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else { return }
        store.save(recipe: recipe)
        dismiss()
    }
}

private struct IngredientInputRow: View {
    @Binding var ingredient: Ingredient

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = (geometry.size.width - 16) / 3
            HStack(spacing: 8) {
                TextField("Ingredient", text: $ingredient.name).figmaInput().frame(width: columnWidth)
                TextField("Quantity", value: $ingredient.quantity, format: .number).figmaInput().frame(width: columnWidth)
                TextField("Measure", text: $ingredient.unit).figmaInput().frame(width: columnWidth)
            }
        }
        .frame(height: 44)
    }
}

struct MealPlanListView: View {
    @EnvironmentObject private var store: MealStore
    @State private var showCreate = false; @State private var query = ""; @State private var selectedTags: Set<String> = []
    private var tags: [String] { Array(Set(store.plans.flatMap(\.tags))).sorted() }
    private var filteredPlans: [MealPlan] { store.plans.filter { plan in (query.isEmpty || plan.name.localizedCaseInsensitiveContains(query) || plan.tags.contains { $0.localizedCaseInsensitiveContains(query) }) && (selectedTags.isEmpty || !selectedTags.isDisjoint(with: Set(plan.tags))) } }
    var body: some View { NavigationStack { ZStack(alignment: .bottomTrailing) { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing: 10) { LibraryHeader(title: "My Meal Plans"); HStack { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query) }.figmaInput(); HStack { MultiSelectFilterMenu(title: "Label", selections: $selectedTags, options: tags); Spacer() }.zIndex(1); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(filteredPlans) { plan in NavigationLink { MealPlanEditor(plan: plan) } label: { PlanCard(plan: plan) } } } }.padding(.horizontal, 16).padding(.bottom, 80) }; Button { showCreate = true } label: { Label("Create Plan", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()) }.padding(.trailing, 20).padding(.bottom, 90) }.sheet(isPresented: $showCreate) { MealPlanEditor(plan: nil) } } }
}

struct PlanCard: View {
    let plan: MealPlan

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let data = plan.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(plan.weekCount.isMultiple(of: 2) ? "FigmaRecipe3" : "FigmaRecipe4").resizable().scaledToFill() }
                }.frame(height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                Text(plan.name).font(.headline).foregroundStyle(AppTheme.text).lineLimit(1)
                Text("\(plan.weekCount) weeks · \(plan.meals.count) meals").font(.caption).foregroundStyle(AppTheme.label)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlanRecipeSlot: Identifiable {
    let week: Int; let weekday: Int; let mealType: MealType
    var id: String { "\(week)-\(weekday)-\(mealType.rawValue)" }
}

struct MealPlanEditor: View {
    @EnvironmentObject private var store: MealStore; @Environment(\.dismiss) private var dismiss
    let existing: MealPlan?
    @State private var name = ""; @State private var tagText = ""; @State private var weekCount = 1; @State private var meals: [PlanMeal] = []; @State private var expandedWeek = 1
    @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?; @State private var recipeSlot: PlanRecipeSlot?
    init(plan: MealPlan?) { existing = plan; _name = State(initialValue: plan?.name ?? ""); _tagText = State(initialValue: plan?.tags.joined(separator: ", ") ?? ""); _weekCount = State(initialValue: plan?.weekCount ?? 1); _meals = State(initialValue: plan?.meals ?? []); _imageData = State(initialValue: plan?.imageData) }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        planHero
                        editorHeader
                        planDetails
                        Text("Plan schedule").font(.custom("Plus Jakarta Sans", size: 21).weight(.bold)).foregroundStyle(AppTheme.text)
                        ForEach(1...weekCount, id: \.self) { week in weekBlock(week) }
                        Button { weekCount += 1; expandedWeek = weekCount } label: { Label("Add Week", systemImage: "plus").font(.custom("Inter", size: 14).weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12).background(AppTheme.input).foregroundStyle(AppTheme.primary).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    }.padding(16).padding(.bottom, 90)
                }.scrollIndicators(.hidden)
                PrimaryButton(title: existing == nil ? "Create Meal Plan" : "Save Changes") { savePlan() }
                    .padding(.horizontal, 16).padding(.bottom, 16).background(AppTheme.background.opacity(0.96))
            }
        }
        .sheet(item: $recipeSlot) { slot in
            PlanRecipePickerSheet(slot: slot) { recipeID in setRecipe(recipeID, for: slot) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            imageData = try? await photoItem.loadTransferable(type: Data.self)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var planHero: some View {
        ZStack(alignment: .topLeading) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.42)) }
                    }.frame(height: 180).frame(maxWidth: .infinity).clipped()
                    Label(imageData == nil ? "Add cover image" : "Change image", systemImage: "photo").font(.custom("Inter", size: 12).weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(AppTheme.input.opacity(0.96)).foregroundStyle(AppTheme.text).clipShape(Capsule()).padding(12)
                }.clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text).frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle()) }.padding(14)
        }
    }

    private var editorHeader: some View {
        Text(existing == nil ? "Create Meal Plan" : "Edit Meal Plan").font(.custom("Plus Jakarta Sans", size: 24).weight(.bold)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planDetails: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plan details").font(.custom("Plus Jakarta Sans", size: 19).weight(.bold)).foregroundStyle(AppTheme.text)
                fieldLabel("Plan name")
                TextField("e.g. Weekday Favorites", text: $name).figmaInput()
                fieldLabel("Labels")
                TextField("e.g. Easy, Family", text: $tagText).figmaInput()
                Text("Add weeks below to build the plan duration.").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
            }
        }
    }

    private func weekBlock(_ week: Int) -> some View {
        let weekMeals = meals.filter { $0.week == week }
        return VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expandedWeek = expandedWeek == week ? 0 : week } } label: {
                HStack { VStack(alignment: .leading, spacing: 3) { Text("Week \(week)").font(.custom("Plus Jakarta Sans", size: 18).weight(.bold)); Text("\(weekMeals.count) meal\(weekMeals.count == 1 ? "" : "s")").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label) }; Spacer(); Image(systemName: expandedWeek == week ? "chevron.up" : "chevron.down").foregroundStyle(AppTheme.label) }.foregroundStyle(AppTheme.text).padding(14)
            }.buttonStyle(.plain)
            if expandedWeek == week {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(1...7, id: \.self) { weekday in daySection(weekday, week: week) }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }.background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func daySection(_ weekday: Int, week: Int) -> some View {
        return VStack(alignment: .leading, spacing: 7) {
            Text(weekdayName(weekday)).font(.custom("Inter", size: 12).weight(.bold)).foregroundStyle(AppTheme.label).padding(.top, 5)
            ForEach(MealType.allCases) { type in mealSlot(weekday: weekday, week: week, type: type) }
        }
    }

    private func mealSlot(weekday: Int, week: Int, type: MealType) -> some View {
        let assigned = meals.first { $0.week == week && $0.weekday == weekday && $0.mealType == type }
        return HStack(spacing: 8) {
            Text(type.displayName).font(.custom("Inter", size: 11).weight(.semibold)).foregroundStyle(AppTheme.text).frame(width: 92, alignment: .leading)
            if let assigned, let recipe = store.recipe(assigned.recipeID) {
                HStack { Text(recipe.title).font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.text).lineLimit(1); Spacer(); Button { meals.removeAll { $0.id == assigned.id } } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.label) } }.padding(.horizontal, 10).frame(height: 29).background(AppTheme.background.opacity(0.55)).clipShape(Capsule())
            } else {
                Button { recipeSlot = PlanRecipeSlot(week: week, weekday: weekday, mealType: type) } label: { HStack { Text("Select recipe").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.label) }.padding(.horizontal, 10).frame(height: 29).background(AppTheme.input).clipShape(Capsule()) }.buttonStyle(.plain)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View { Text(title).font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.label) }
    private func setRecipe(_ recipeID: UUID, for slot: PlanRecipeSlot) { meals.removeAll { $0.week == slot.week && $0.weekday == slot.weekday && $0.mealType == slot.mealType }; meals.append(PlanMeal(week: slot.week, weekday: slot.weekday, mealType: slot.mealType, recipeID: recipeID)) }
    private func savePlan() { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.save(plan: MealPlan(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), tags: tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, weekCount: weekCount, meals: meals.filter { $0.week <= weekCount }, imageData: imageData)); dismiss() }
}

private struct PlanRecipePickerSheet: View {
    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    let slot: PlanRecipeSlot
    let select: (UUID) -> Void
    @State private var query = ""
    private var recipes: [Recipe] { store.recipes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) } } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack { Spacer().frame(width: 30); Spacer(); Text("Choose Recipe").font(.custom("Plus Jakarta Sans", size: 26).weight(.bold)).foregroundStyle(AppTheme.text); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) } }
                    Text("\(weekdayName(slot.weekday)) · \(slot.mealType.displayName)").font(.custom("Inter", size: 13)).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search recipes", text: $query).foregroundStyle(AppTheme.text) }.padding(.horizontal, 12).frame(height: 36).background(AppTheme.input).clipShape(Capsule())
                    ScrollView { LazyVStack(spacing: 9) { ForEach(recipes) { recipe in Button { select(recipe.id); dismiss() } label: { HStack(spacing: 10) { Image(recipe.title == "Apple Pie" ? "FigmaRecipe2" : "FigmaRecipe3").resizable().scaledToFill().frame(width: 56, height: 56).clipShape(Circle()); VStack(alignment: .leading, spacing: 3) { Text(recipe.title).font(.custom("Plus Jakarta Sans", size: 17).weight(.semibold)).foregroundStyle(AppTheme.text); Text(recipe.author).font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label); HStack(spacing: 6) { ForEach(recipe.tags.prefix(2), id: \.self) { Tag(title: $0) } } }; Spacer() }.padding(9).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) } }.padding(.bottom, 12) }.scrollIndicators(.hidden)
                }.padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }
}

struct PlanMealRow: View { @EnvironmentObject private var store: MealStore; let meal: PlanMeal; var body: some View { HStack { Image(systemName: meal.mealType.symbol).foregroundStyle(AppTheme.primary).frame(width: 22); VStack(alignment: .leading) { Text("\(weekdayName(meal.weekday)) · \(meal.mealType.displayName)"); Text(store.recipe(meal.recipeID)?.title ?? "Missing recipe").font(.caption).foregroundStyle(AppTheme.label) } } } }
func weekdayName(_ weekday: Int) -> String { Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))] }

struct AddPlanMealButton: View {
    @EnvironmentObject private var store: MealStore; let week: Int; let add: (PlanMeal) -> Void
    @State private var type: MealType = .breakfast; @State private var weekday = 2; @State private var recipeID: UUID?
    var body: some View { Menu { Picker("Day", selection: $weekday) { ForEach(1...7, id: \.self) { Text(weekdayName($0)).tag($0) } }; Picker("Meal type", selection: $type) { ForEach(MealType.allCases) { Text($0.rawValue).tag($0) } }; Picker("Recipe", selection: $recipeID) { Text("Choose recipe").tag(UUID?.none); ForEach(store.recipes) { Text($0.title).tag(Optional($0.id)) } }; Button("Add Meal") { if let recipeID { add(PlanMeal(week: week, weekday: weekday, mealType: type, recipeID: recipeID)) } } } label: { Label("Add Meal", systemImage: "plus") } }
}

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month"
    var id: Self { self }
}

struct CalendarView: View {
    @EnvironmentObject private var store: MealStore
    @State private var selectedDate = Date()
    @State private var displayMode: CalendarDisplayMode = .week
    @State private var showMeal = false
    @State private var showPlan = false
    @State private var mealTypeToAdd: MealType?
    @State private var mealSheetDetent: PresentationDetent = .large
    @State private var planSheetDetent: PresentationDetent = .large
    @State private var weekFeedDates: [Date] = []
    @State private var weekBarAnchor = Date()
    @State private var selectedRecipe: Recipe?
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.background.ignoresSafeArea()
                Group {
                    if displayMode == .week {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                modePicker
                                weekView
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .background(AppTheme.background)
                            .zIndex(1)
                            Divider().overlay(AppTheme.surface)
                            ScrollView {
                                weekDayFeed
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 92)
                            }
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                modePicker
                                monthView
                                selectedDayMeals
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 92)
                        }
                    }
                }
                actionButtons.padding(.trailing, 20).padding(.bottom, 90)
            }
            .navigationBarHidden(true)
            .onAppear { weekBarAnchor = selectedDate; loadWeekFeed(from: selectedDate) }
            .sheet(isPresented: $showMeal) {
                ScheduleMealSheet(date: selectedDate, initialType: mealTypeToAdd)
                    .presentationDetents([.medium, .large], selection: $mealSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showPlan) {
                ApplyPlanSheet(startDate: selectedDate)
                    .presentationDetents([.medium, .large], selection: $planSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(item: $selectedRecipe) { recipe in RecipeDetailView(recipe: recipe) }
        }
    }

    private var header: some View { LibraryHeader(title: "Meal Planning") }

    private var modePicker: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    Button(mode.rawValue) { withAnimation(.easeInOut(duration: 0.18)) { displayMode = mode } }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayMode.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.text)
                .padding(.horizontal, 11).frame(height: 25)
                .background(Color(red: 37/255, green: 31/255, blue: 48/255))
                .overlay(Capsule().stroke(AppTheme.input, lineWidth: 1)).clipShape(Capsule())
            }
        }
    }

    private var weekView: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarTitle
            HStack(spacing: 8) {
                ForEach(-3...3, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: weekBarAnchor) ?? weekBarAnchor
                    dayButton(day, compact: true)
                }
            }
        }
    }

    private var weekDayFeed: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(weekFeedDates, id: \.self) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.formatted(date: .complete, time: .omitted)).font(.custom("Plus Jakarta Sans", size: 20).weight(.semibold)).foregroundStyle(AppTheme.text)
                    ForEach(MealType.allCases) { type in weeklyMealSlot(type, for: day) }
                }
                .id(calendar.startOfDay(for: day))
                .onAppear {
                    if let last = weekFeedDates.last, calendar.isDate(day, inSameDayAs: last) { appendWeekFeed() }
                    selectedDate = day
                    advanceWeekBarIfNeeded(for: day)
                }
            }
        }
    }

    private var monthView: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarTitle
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) {
                    Text(String($0.prefix(1))).font(.custom("Inter", size: 11).weight(.semibold)).foregroundStyle(AppTheme.label).frame(height: 30)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayButton(day, compact: false) } else { Color.clear.frame(height: 70).overlay(Rectangle().stroke(AppTheme.surface, lineWidth: 0.5)) }
                }
            }
            .padding(.horizontal, 5)
        }
    }

    private var calendarTitle: some View {
        HStack {
            Button { moveCalendar(by: displayMode == .month ? -1 : -7) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text((displayMode == .month ? selectedDate : weekBarAnchor).formatted(.dateTime.month(.wide).year()))
                .font(.custom("Plus Jakarta Sans", size: 18).weight(.semibold)).foregroundStyle(AppTheme.text)
            Spacer()
            Button { moveCalendar(by: displayMode == .month ? 1 : 7) } label: { Image(systemName: "chevron.right") }
        }.foregroundStyle(AppTheme.text).padding(.horizontal, 4)
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate),
              let dayRange = calendar.range(of: .day, in: .month, for: selectedDate) else { return [] }
        let leading = calendar.component(.weekday, from: interval.start) - calendar.firstWeekday
        let adjustedLeading = leading < 0 ? leading + 7 : leading
        let dateCells = dayRange.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        let days = [Date?](repeating: nil, count: adjustedLeading) + dateCells
        return days + Array(repeating: nil, count: max(0, 42 - days.count))
    }

    private func dayButton(_ day: Date, compact: Bool) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: compact ? weekBarAnchor : selectedDate)
        return Button { selectedDate = day; if compact { weekBarAnchor = day } } label: {
            VStack(spacing: compact ? 4 : 3) {
                if compact { Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption) }
                if compact {
                    Text(day.formatted(.dateTime.day())).font(.headline)
                } else {
                    Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(selected ? AppTheme.mealIndicator.opacity(0.45) : Color.clear)
                        .clipShape(Circle())
                }
                if !compact {
                    monthStatusCluster(for: day)
                }
            }
            .frame(maxWidth: .infinity).frame(height: compact ? 58 : 70)
            .background(compact && selected ? AppTheme.primary : Color.clear)
            .foregroundStyle(compact && selected ? .black : AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 0))
            .overlay { if !compact { Rectangle().stroke(AppTheme.surface, lineWidth: 0.5) } }
        }.buttonStyle(.plain)
    }

    private func monthStatusCluster(for day: Date) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { ForEach(Array(MealType.allCases.prefix(3))) { mealStatusBubble(for: day, type: $0) } }
            HStack(spacing: 2) { ForEach(Array(MealType.allCases.suffix(2))) { mealStatusBubble(for: day, type: $0) } }
        }
    }

    private func mealStatusBubble(for day: Date, type: MealType) -> some View {
        let isScheduled = store.meals(on: day).contains { $0.mealType == type }
        return Circle()
            .fill(isScheduled ? AppTheme.mealIndicator : Color.clear)
            .overlay(Circle().stroke(AppTheme.mealIndicator, lineWidth: 1))
            .frame(width: 7, height: 7)
    }

    private var selectedDayMeals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(date: .complete, time: .omitted)).font(.custom("Plus Jakarta Sans", size: 20).weight(.semibold)).foregroundStyle(AppTheme.text)
            if store.meals(on: selectedDate).isEmpty {
                Text("No meals planned").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label).padding(.vertical, 16).frame(maxWidth: .infinity).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(store.meals(on: selectedDate)) { scheduled in
                    if let recipe = store.recipe(scheduled.recipeID) {
                        scheduledMealCard(scheduled, recipe: recipe)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weeklyMealSlot(_ type: MealType, for date: Date) -> some View {
        let scheduled = store.meals(on: date).first { $0.mealType == type }
        if let scheduled, let recipe = store.recipe(scheduled.recipeID) {
            scheduledMealCard(scheduled, recipe: recipe)
        } else {
            Button { selectedDate = date; mealTypeToAdd = type; mealSheetDetent = .large; showMeal = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.headline.weight(.bold)).foregroundStyle(AppTheme.primary).frame(width: 50, height: 50).background(AppTheme.input).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(type.displayName.uppercased()).font(.custom("Inter", size: 10).weight(.bold)).foregroundStyle(AppTheme.label)
                        Text("Add \(type.displayName)").font(.custom("Plus Jakarta Sans", size: 16).weight(.semibold)).foregroundStyle(AppTheme.text)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.label)
                }
                .padding(12).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
    }

    private func scheduledMealCard(_ scheduled: CalendarMeal, recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            Image(scheduled.mealType == .dinner ? "FigmaRecipe1" : "FigmaRecipe3")
                .resizable().scaledToFill().frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(scheduled.mealType.displayName.uppercased()).font(.custom("Inter", size: 10).weight(.bold)).foregroundStyle(AppTheme.label)
                Text(recipe.title).font(.custom("Plus Jakarta Sans", size: 15).weight(.semibold)).foregroundStyle(AppTheme.text)
            }
            Spacer()
            Button(role: .destructive) { store.calendarMeals.removeAll { $0.id == scheduled.id } } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(AppTheme.label).frame(width: 32, height: 32).background(AppTheme.input).clipShape(Circle()) }
        }
        .padding(12).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { selectedRecipe = recipe }
    }

    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button { planSheetDetent = .large; showPlan = true } label: { Label("Apply plan", systemImage: "square.stack.3d.up.fill").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 11).background(AppTheme.surface).foregroundStyle(AppTheme.text).clipShape(Capsule()) }
            Button { mealTypeToAdd = nil; mealSheetDetent = .large; showMeal = true } label: { Label("Add Meal", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()) }
        }
    }

    private func moveCalendar(by amount: Int) {
        if displayMode == .month {
            selectedDate = calendar.date(byAdding: .month, value: amount, to: selectedDate) ?? selectedDate
        } else {
            weekBarAnchor = calendar.date(byAdding: .day, value: amount, to: weekBarAnchor) ?? weekBarAnchor
            selectedDate = weekBarAnchor
        }
    }

    private func loadWeekFeed(from date: Date) {
        let start = calendar.startOfDay(for: date)
        weekFeedDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func appendWeekFeed() {
        guard let last = weekFeedDates.last else { loadWeekFeed(from: selectedDate); return }
        let next = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: last) }
        weekFeedDates.append(contentsOf: next)
    }

    private func advanceWeekBarIfNeeded(for day: Date) {
        guard let firstVisible = calendar.date(byAdding: .day, value: -3, to: weekBarAnchor),
              let lastVisible = calendar.date(byAdding: .day, value: 3, to: weekBarAnchor) else { return }
        if day > lastVisible {
            weekBarAnchor = calendar.date(byAdding: .day, value: 7, to: weekBarAnchor) ?? day
        } else if day < firstVisible {
            weekBarAnchor = calendar.date(byAdding: .day, value: -7, to: weekBarAnchor) ?? day
        }
    }
}

struct ScheduleMealSheet: View {
    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var type: MealType?
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var pendingRecipe: Recipe?

    init(date: Date, initialType: MealType? = nil) { self.date = date; _type = State(initialValue: initialType) }

    private var tags: [String] { Array(Set(store.recipes.flatMap(\.tags))).sorted() }
    private var filteredRecipes: [Recipe] {
        store.recipes.filter { recipe in
            (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.author.localizedCaseInsensitiveContains(query) || recipe.tags.contains { $0.localizedCaseInsensitiveContains(query) }) &&
            (selectedTag == nil || recipe.tags.contains(selectedTag!))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Spacer().frame(width: 30)
                        Spacer()
                        Text("Add Meal").font(.custom("Plus Jakarta Sans", size: 28).weight(.bold)).foregroundStyle(AppTheme.text)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.weight(.medium)).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) }
                    }
                    if let pendingRecipe {
                        mealTypeConfirmation(for: pendingRecipe)
                    } else {
                        Text(type == nil ? "Choose a recipe to add to this day" : "Add a recipe for \(type!.displayName.lowercased())")
                            .font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query).foregroundStyle(AppTheme.text) }
                                .padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule())
                            Menu {
                                Button("All Labels") { selectedTag = nil }
                                ForEach(tags, id: \.self) { tag in Button(tag) { selectedTag = tag } }
                            } label: {
                                HStack(spacing: 4) { Text(selectedTag ?? "Label"); Image(systemName: "chevron.down").font(.caption2) }
                                    .font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label).padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule())
                            }
                        }
                        ScrollView {
                            LazyVStack(spacing: 9) {
                                if filteredRecipes.isEmpty {
                                    Text("No recipes found").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label).padding(.top, 30)
                                } else {
                                    ForEach(filteredRecipes) { recipe in recipeRow(recipe) }
                                }
                            }.padding(.top, 1).padding(.bottom, 12)
                        }.scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        Button {
            if let type {
                store.schedule(recipeID: recipe.id, on: date, type: type, replacing: true)
                dismiss()
            } else {
                pendingRecipe = recipe
            }
        } label: {
            RecipeSelectionCard(recipe: recipe)
        }.buttonStyle(.plain)
    }

    private func mealTypeConfirmation(for recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { pendingRecipe = nil; type = nil } label: { Label("Back to recipes", systemImage: "chevron.left").font(.custom("Inter", size: 13).weight(.semibold)).foregroundStyle(AppTheme.label) }
            RecipeSelectionCard(recipe: recipe)
            Text("Which meal is this for?").font(.custom("Plus Jakarta Sans", size: 20).weight(.bold)).foregroundStyle(AppTheme.text)
            ForEach(MealType.allCases) { mealType in
                Button { type = mealType } label: {
                    HStack { Text(mealType.rawValue).font(.custom("Inter", size: 15).weight(.semibold)); Spacer(); Image(systemName: type == mealType ? "checkmark.circle.fill" : "circle").font(.title3) }
                        .foregroundStyle(type == mealType ? .black : AppTheme.text).padding(.horizontal, 14).frame(height: 48).background(type == mealType ? AppTheme.primary : AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            PrimaryButton(title: "Confirm Meal") {
                guard let type else { return }
                store.schedule(recipeID: recipe.id, on: date, type: type, replacing: true)
                dismiss()
            }.disabled(type == nil)
        }
    }
}

struct ApplyPlanSheet: View {
    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    let startDate: Date
    @State private var planID: UUID?
    @State private var start: Date
    @State private var end: Date
    @State private var replace = false
    @State private var step = 1
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var showStartCalendar = false
    @State private var showEndCalendar = false

    init(startDate: Date) { self.startDate = startDate; _start = State(initialValue: startDate); _end = State(initialValue: Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate) }
    private var tags: [String] { Array(Set(store.plans.flatMap(\.tags))).sorted() }
    private var filteredPlans: [MealPlan] { store.plans.filter { (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }) && (selectedTag == nil || $0.tags.contains(selectedTag!)) } }
    private var selectedPlan: MealPlan? { store.plans.first { $0.id == planID } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    header
                    if step == 1 { planPicker } else { planConfirmation }
                }.padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private var header: some View {
        HStack {
            if step == 2 { Button { step = 1 } label: { Image(systemName: "chevron.left").font(.headline).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) } } else { Color.clear.frame(width: 30, height: 30) }
            Spacer()
            Text(step == 1 ? "Add Meal Plan" : "Apply Meal Plan").font(.custom("Plus Jakarta Sans", size: 27).weight(.bold)).foregroundStyle(AppTheme.text)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.weight(.medium)).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) }
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query).foregroundStyle(AppTheme.text) }.padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule())
                Menu { Button("All Labels") { selectedTag = nil }; ForEach(tags, id: \.self) { tag in Button(tag) { selectedTag = tag } } } label: { HStack(spacing: 4) { Text(selectedTag ?? "Label"); Image(systemName: "chevron.down").font(.caption2) }.font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label).padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule()) }
            }
            ScrollView { LazyVStack(spacing: 9) { ForEach(filteredPlans) { plan in planRow(plan) } }.padding(.bottom, 12) }.scrollIndicators(.hidden)
        }
    }

    private func planRow(_ plan: MealPlan) -> some View {
        Button { planID = plan.id; step = 2 } label: {
            HStack(spacing: 10) {
                Image(plan.weekCount.isMultiple(of: 2) ? "FigmaRecipe3" : "FigmaRecipe4").resizable().scaledToFill().frame(width: 58, height: 58).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) { Text(plan.name).font(.custom("Plus Jakarta Sans", size: 18).weight(.semibold)).foregroundStyle(AppTheme.text); Text("\(plan.weekCount) week\(plan.weekCount == 1 ? "" : "s") · \(plan.meals.count) meals").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label); HStack(spacing: 6) { ForEach(plan.tags.prefix(2), id: \.self) { Tag(title: $0) } } }
                Spacer(minLength: 0)
            }.padding(9).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var planConfirmation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let plan = selectedPlan { planRow(plan).disabled(true) }
                Text("Choose the time period").font(.custom("Plus Jakarta Sans", size: 19).weight(.bold)).foregroundStyle(AppTheme.text)
                SurfaceCard { VStack(spacing: 8) { dateRow(title: "Start", date: $start, isExpanded: $showStartCalendar); Divider().overlay(AppTheme.border); dateRow(title: "End", date: $end, isExpanded: $showEndCalendar, range: start...) } }
                Text("Existing meals").font(.custom("Plus Jakarta Sans", size: 19).weight(.bold)).foregroundStyle(AppTheme.text)
                VStack(spacing: 8) {
                    Button { replace = true } label: { overwriteOption(title: "Replace existing meals", selected: replace) }.buttonStyle(.plain)
                    Button { replace = false } label: { overwriteOption(title: "Keep existing meals", selected: !replace) }.buttonStyle(.plain)
                }
                Text("Plans repeat from Week 1 when the selected range is longer than the plan.").font(.footnote).foregroundStyle(AppTheme.label)
                PrimaryButton(title: "Apply Plan") { if let plan = selectedPlan { store.apply(plan: plan, from: start, through: end, replaceExisting: replace); dismiss() } }
            }.padding(.bottom, 18)
        }.scrollIndicators(.hidden)
    }

    private func overwriteOption(title: String, selected: Bool) -> some View {
        HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? AppTheme.primary : AppTheme.label); Text(title).font(.custom("Inter", size: 15).weight(.semibold)).foregroundStyle(AppTheme.text); Spacer() }.padding(.horizontal, 14).frame(height: 48).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func dateRow(title: String, date: Binding<Date>, isExpanded: Binding<Bool>, range: PartialRangeFrom<Date>? = nil) -> some View {
        Button { isExpanded.wrappedValue.toggle() } label: {
            HStack { Text(title).font(.custom("Inter", size: 14).weight(.semibold)).foregroundStyle(AppTheme.text); Spacer(); Text(planDateString(date.wrappedValue)).font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label); Image(systemName: "calendar").foregroundStyle(AppTheme.primary) }.padding(.vertical, 5)
        }.buttonStyle(.plain)
        if isExpanded.wrappedValue {
            if let range { DatePicker("", selection: date, in: range, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().tint(AppTheme.primary) }
            else { DatePicker("", selection: date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().tint(AppTheme.primary) }
        }
    }

    private func planDateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }
}
