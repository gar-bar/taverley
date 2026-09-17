import SwiftUI
import PhotosUI
import UIKit

struct FeedView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var query = ""
    @State private var activeSheet: FeedSheet?
    @State private var showSignInPrompt = false
    @State private var composeAfterProfileSetup = false

    private var filteredItems: [FeedItem] {
        feedStore.items.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 10) {
                    searchBar
                        .padding(.horizontal, 16)

                    feedContent
                }
            }
            .navigationTitle("My Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createPost) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(AppTheme.primary)
                    .foregroundStyle(.black)
                    .accessibilityLabel("Create post")
                }
            }
            .sheet(item: $activeSheet, onDismiss: {
                if composeAfterProfileSetup {
                    composeAfterProfileSetup = false
                    activeSheet = .composer
                }
            }) { sheet in
                switch sheet {
                case .profile:
                    ProfileSetupView {
                        composeAfterProfileSetup = true
                        activeSheet = nil
                    }
                case .composer:
                    PostComposerView()
                }
            }
            .alert("Sign in to post", isPresented: $showSignInPrompt) {
                Button("Not now", role: .cancel) { }
                Button("Sign in") { authentication.isSkippingForNow = false }
            } message: {
                Text("You can browse the demo feed as a guest. Sign in to publish to the shared feed.")
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.label)
            TextField("Search posts, people, recipes, ingredients", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppTheme.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.label)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(AppTheme.input)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var feedContent: some View {
        if feedStore.isLoading && feedStore.items.isEmpty {
            Spacer()
            ProgressView("Loading feed…")
                .tint(AppTheme.primary)
                .foregroundStyle(AppTheme.label)
            Spacer()
        } else if let error = feedStore.errorMessage, feedStore.items.isEmpty {
            Spacer()
            ContentUnavailableView {
                Label("Couldn’t load the feed", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { try? await feedStore.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
            }
            Spacer()
        } else if filteredItems.isEmpty {
            Spacer()
            ContentUnavailableView(
                query.isEmpty ? "No posts yet" : "No matching posts",
                systemImage: query.isEmpty ? "text.bubble" : "magnifyingglass",
                description: Text(query.isEmpty ? "Be the first person to share something." : "Try a different username, title, recipe, or ingredient.")
            )
            Spacer()
        } else {
            List {
                if let error = feedStore.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(AppTheme.primary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppTheme.label)
                            .lineLimit(2)
                        Spacer()
                        Button("Retry") { Task { try? await feedStore.refresh() } }
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(AppTheme.surface)
                }
                ForEach(filteredItems) { item in
                    FeedPostCard(item: item)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(AppTheme.border)
                        .listRowBackground(AppTheme.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 78, for: .scrollContent)
            .refreshable { try? await feedStore.refresh() }
        }
    }

    private func createPost() {
        guard feedStore.isAuthenticated else {
            showSignInPrompt = true
            return
        }
        activeSheet = feedStore.currentProfile == nil ? .profile : .composer
    }
}

private enum FeedSheet: String, Identifiable {
    case profile, composer
    var id: String { rawValue }
}

private struct FeedPostCard: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.post.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.post.body)
                        .font(.body)
                        .foregroundStyle(AppTheme.text.opacity(0.92))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.post.photoPaths.isEmpty {
                        PostPhotoGrid(paths: item.post.photoPaths)
                            .padding(.top, 5)
                    }
                }

                if let recipe = item.recipe {
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        FeedRecipeSummary(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 144)
                    .accessibilityLabel("Open recipe \(recipe.title)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }

    private var authorRow: some View {
        HStack(spacing: 9) {
            Text(item.author.displayName.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(AppTheme.primary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(item.author.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.text)
                Text("@\(item.author.username)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.label)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Posted by \(item.author.displayName), at \(item.author.username)")
    }
}

private struct FeedRecipeSummary: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(2)

            Text("Ingredients")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.text)

            ForEach(recipe.ingredients.prefix(6)) { ingredient in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("•")
                        .foregroundStyle(AppTheme.primary)
                    Text(ingredient.display)
                        .foregroundStyle(AppTheme.text.opacity(0.82))
                        .lineLimit(1)
                }
                .font(.caption2)
            }

            if recipe.ingredients.count > 6 {
                Text("+ \(recipe.ingredients.count - 6) more")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.input)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct PostPhotoGrid: View {
    let paths: [String]
    private let spacing: CGFloat = 7

    var body: some View {
        let visible = Array(paths.prefix(4))
        Group {
            if visible.count == 1 {
                PostPhoto(path: visible[0])
                    .frame(height: 150)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible())], spacing: spacing) {
                    ForEach(visible, id: \.self) { path in
                        PostPhoto(path: path)
                            .frame(height: visible.count == 2 ? 105 : 82)
                    }
                }
            }
        }
    }
}

private struct PostPhoto: View {
    @EnvironmentObject private var feedStore: FeedStore
    let path: String

    var body: some View {
        Group {
            if path.hasPrefix("asset:") {
                Image(String(path.dropFirst("asset:".count)))
                    .resizable()
                    .scaledToFill()
            } else if let data = feedStore.photoData[path], let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AppTheme.surface
                    ProgressView().tint(AppTheme.primary)
                }
                .task(id: path) { await feedStore.loadPhoto(path: path) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Post photo")
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var authentication: AuthenticationStore
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var displayName = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UsernamePolicy.isValid(username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your feed identity")
                } footer: {
                    Text("Usernames use 3–30 lowercase letters, numbers, periods, or underscores and must be unique.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Create Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .onAppear {
            let email = authentication.session?.user.email
            username = UsernamePolicy.suggestion(from: email)
            displayName = email?.split(separator: "@").first.map { String($0).replacingOccurrences(of: ".", with: " ").capitalized } ?? ""
        }
    }

    private func save() {
        Task {
            isSaving = true
            errorMessage = nil
            do {
                try await feedStore.saveProfile(displayName: displayName, username: username)
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct PostComposerView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var selectedRecipe: Recipe?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var showRecipePicker = false
    @State private var isPublishing = false
    @State private var errorMessage: String?

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photos.count <= 4
            && !isPublishing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add Title", text: $title)
                        .font(.headline)

                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Add Post Details")
                                    .foregroundStyle(AppTheme.label)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Recipe") {
                    if let selectedRecipe {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .foregroundStyle(AppTheme.primary)
                            VStack(alignment: .leading) {
                                Text(selectedRecipe.title)
                                Text("\(selectedRecipe.ingredients.count) ingredients")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.label)
                            }
                            Spacer()
                            Button(role: .destructive) { self.selectedRecipe = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove linked recipe")
                        }
                    } else {
                        Button("Add Recipe", systemImage: "plus") { showRecipePicker = true }
                    }
                }

                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Label(photos.isEmpty ? "Add Photos" : "Choose Different Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if !photos.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                                if let image = UIImage(data: data) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 110)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Button { removePhoto(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                        .accessibilityLabel("Remove photo \(index + 1)")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Photos")
                        Spacer()
                        Text("\(photos.count)/4")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .disabled(isPublishing)
                        .accessibilityLabel("Close post composer")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish", action: publish)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                        .disabled(!canPublish)
                }
            }
            .sheet(isPresented: $showRecipePicker) {
                FeedRecipePicker(selectedRecipe: $selectedRecipe)
            }
            .task(id: photoItems) { await loadSelectedPhotos() }
            .overlay {
                if isPublishing {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Publishing…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func loadSelectedPhotos() async {
        var loaded: [Data] = []
        for item in photoItems.prefix(4) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let compressed = UIImage(data: data)?.postJPEGData()
            else { continue }
            loaded.append(compressed)
        }
        photos = loaded
    }

    private func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if photoItems.indices.contains(index) { photoItems.remove(at: index) }
    }

    private func publish() {
        Task {
            isPublishing = true
            errorMessage = nil
            do {
                try await feedStore.publish(title: title, body: details, recipe: selectedRecipe, photos: photos)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isPublishing = false
        }
    }
}

private struct FeedRecipePicker: View {
    @EnvironmentObject private var mealStore: MealStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRecipe: Recipe?
    @State private var query = ""

    private var filteredRecipes: [Recipe] {
        mealStore.recipes.filter { recipe in
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty
                || recipe.title.localizedCaseInsensitiveContains(query)
                || recipe.ingredients.contains { $0.display.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredRecipes) { recipe in
                Button {
                    selectedRecipe = recipe
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.primary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.title).foregroundStyle(AppTheme.text)
                            Text("\(recipe.ingredients.count) ingredients")
                                .font(.caption)
                                .foregroundStyle(AppTheme.label)
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search recipes or ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

private extension UIImage {
    func postJPEGData(maxDimension: CGFloat = 1_600, quality: CGFloat = 0.82) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: targetSize)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

private extension String {
    var initials: String {
        split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
