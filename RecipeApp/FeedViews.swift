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
    @State private var selectedPostID: UUID?

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
            .navigationDestination(item: $selectedPostID) { postID in
                PostDetailView(postID: postID)
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
                    FeedPostCard(item: item) {
                        selectedPostID = item.id
                    }
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

struct FeedPostCard: View {
    @EnvironmentObject private var feedStore: FeedStore
    let item: FeedItem
    let onOpen: () -> Void
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var operationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Button(action: onOpen) {
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
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open post \(item.post.title)")

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
                    .frame(width: 120)
                    .accessibilityLabel("Open recipe \(recipe.title)")
                }
            }

            PostEngagementBar(postID: item.id, onComment: onOpen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background)
        .sheet(isPresented: $showEditor) {
            PostComposerView(editing: item)
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Post", role: .destructive) { deletePost() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the post and its photos from the shared feed.")
        }
        .alert("Couldn’t delete post", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "Please try again.")
        }
    }

    private var authorRow: some View {
        HStack(spacing: 9) {
            Button(action: onOpen) {
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open post by \(item.author.displayName), at \(item.author.username)")

            Spacer()

            if feedStore.currentUserID == item.post.authorID {
                Menu {
                    Button("Edit Post", systemImage: "pencil") { showEditor = true }
                    Button("Delete Post", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(AppTheme.label)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Post options")
            }
        }
    }

    private func deletePost() {
        Task {
            do {
                try await feedStore.delete(post: item.post)
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}

private struct PostEngagementBar: View {
    @EnvironmentObject private var feedStore: FeedStore
    let postID: UUID
    let onComment: () -> Void
    @State private var errorMessage: String?

    private var isLiked: Bool { feedStore.likedPostIDs.contains(postID) }
    private var isFavourited: Bool { feedStore.favouritedPostIDs.contains(postID) }
    private var likeCount: Int { feedStore.likeCount(for: postID) }
    private var commentCount: Int { feedStore.comments(for: postID).count }

    var body: some View {
        HStack(spacing: 20) {
            Button { update { try await feedStore.togglePostLike(postID: postID) } } label: {
                HStack(spacing: 5) {
                    Image("IconlyHeart")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                    if likeCount > 0 { Text("\(likeCount)") }
                }
                .foregroundStyle(isLiked ? AppTheme.primary : AppTheme.label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "Unlike post" : "Like post")

            Button(action: onComment) {
                HStack(spacing: 5) {
                    Image("IconlyChat")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                    if commentCount > 0 { Text("\(commentCount)") }
                }
                .foregroundStyle(AppTheme.label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(commentCount == 1 ? "Open 1 comment" : "Open \(commentCount) comments")

            Spacer()

            Button { update { try await feedStore.togglePostFavourite(postID: postID) } } label: {
                Image(systemName: isFavourited ? "star.fill" : "star")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isFavourited ? AppTheme.primary : AppTheme.label)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavourited ? "Remove post from favourites" : "Favourite post")
        }
        .font(.caption.weight(.semibold))
        .alert("Couldn’t update post", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func update(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct PostDetailView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    let postID: UUID
    @State private var commentText = ""
    @State private var commentError: String?
    @FocusState private var isCommentFocused: Bool

    private var item: FeedItem? {
        feedStore.items.first { $0.id == postID }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if let item {
                ScrollView {
                    VStack(spacing: 0) {
                        PostDetailPhotoHeader(paths: item.post.photoPaths) {
                            dismiss()
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            detailAuthorRow(item.author)

                            Text(item.post.title)
                                .font(.custom("Plus Jakarta Sans", size: 28).weight(.bold))
                                .foregroundStyle(AppTheme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)

                            Text(item.post.body)
                                .font(.custom("Inter", size: 16))
                                .foregroundStyle(AppTheme.text.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            PostEngagementBar(postID: item.id) {
                                isCommentFocused = true
                            }

                            if let recipe = item.recipe {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("Linked Recipe")
                                        .font(.custom("Plus Jakarta Sans", size: 20).weight(.semibold))
                                        .foregroundStyle(AppTheme.text)

                                    NavigationLink {
                                        RecipeDetailView(recipe: recipe)
                                    } label: {
                                        FeedRecipeSummary(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open recipe \(recipe.title)")
                                }
                            }

                            commentsSection(for: item.id)
                        }
                        .padding(16)
                        .padding(.bottom, 28)
                        .background(AppTheme.background)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                        .offset(y: item.post.photoPaths.isEmpty ? 0 : -14)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("Post unavailable", systemImage: "text.bubble")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Couldn’t add comment", isPresented: Binding(
            get: { commentError != nil },
            set: { if !$0 { commentError = nil } }
        )) {
            Button("OK") { commentError = nil }
        } message: {
            Text(commentError ?? "Please try again.")
        }
    }

    private func detailAuthorRow(_ author: UserProfile) -> some View {
        HStack(spacing: 9) {
            Text(author.displayName.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(AppTheme.primary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(author.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.text)
                Text("@\(author.username)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.label)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Posted by \(author.displayName), at \(author.username)")
    }

    private func commentsSection(for postID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.custom("Plus Jakarta Sans", size: 20).weight(.semibold))
                .foregroundStyle(AppTheme.text)

            let comments = feedStore.comments(for: postID)
            if comments.isEmpty {
                Text("Be the first to comment.")
                    .font(.custom("Inter", size: 14))
                    .foregroundStyle(AppTheme.label)
            } else {
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 9) {
                        Text(comment.author.displayName.initials)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.primary)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.author.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.text)
                            Text(comment.comment.body)
                                .font(.custom("Inter", size: 14))
                                .foregroundStyle(AppTheme.text.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a comment", text: $commentText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.custom("Inter", size: 15))
                    .foregroundStyle(AppTheme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($isCommentFocused)

                Button("Post") { submitComment(to: postID) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func submitComment(to postID: UUID) {
        Task {
            do {
                try await feedStore.addComment(to: postID, body: commentText)
                commentText = ""
                isCommentFocused = false
            } catch {
                commentError = error.localizedDescription
            }
        }
    }
}

private struct PostDetailPhotoHeader: View {
    let paths: [String]
    let onBack: () -> Void
    @State private var currentIndex = 0
    @State private var expandedPhoto: PostPhotoSelection?

    private var visiblePaths: [String] { Array(paths.prefix(4)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if visiblePaths.isEmpty {
                AppTheme.surface
                    .frame(height: 72)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(visiblePaths.enumerated()), id: \.offset) { index, path in
                        PostPhotoContent(path: path, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipped()
                            .overlay(AppTheme.background.opacity(0.2))
                            .contentShape(Rectangle())
                            .onTapGesture { expandedPhoto = PostPhotoSelection(index: index) }
                            .accessibilityLabel("Open photo \(index + 1) of \(visiblePaths.count) full screen")
                            .tag(index)
                    }
                }
                .frame(height: 240)
                .tabViewStyle(.page(indexDisplayMode: visiblePaths.count > 1 ? .always : .never))
            }

            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.background.opacity(0.94))
                    .clipShape(Circle())
            }
            .padding(14)
            .accessibilityLabel("Back")
        }
        .fullScreenCover(item: $expandedPhoto) { selection in
            PostPhotoViewer(paths: visiblePaths, initialIndex: selection.index)
        }
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
    private let thumbnailSize: CGFloat = 88
    private let spacing: CGFloat = 9
    @State private var selection: PostPhotoSelection?

    private var visiblePaths: [String] { Array(paths.prefix(4)) }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            photoButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $selection) { selection in
            PostPhotoViewer(paths: visiblePaths, initialIndex: selection.index)
        }
    }

    @ViewBuilder
    private var photoButtons: some View {
        ForEach(Array(visiblePaths.enumerated()), id: \.offset) { index, path in
            photoButton(path: path, index: index)
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
    }

    private func photoButton(path: String, index: Int) -> some View {
        Button {
            selection = PostPhotoSelection(index: index)
        } label: {
            PostPhoto(path: path)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open photo \(index + 1) of \(visiblePaths.count) full screen")
    }
}

private struct PostPhoto: View {
    let path: String

    var body: some View {
        PostPhotoContent(path: path, contentMode: .fill)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Post photo")
    }
}

private struct PostPhotoSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct PostPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let paths: [String]
    @State private var selectedIndex: Int

    init(paths: [String], initialIndex: Int) {
        self.paths = paths
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    PostPhotoContent(path: path, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 64)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: paths.count > 1 ? .always : .never))

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
            .accessibilityLabel("Close full-screen photo")
        }
        .preferredColorScheme(.dark)
    }
}

private struct PostPhotoContent: View {
    @EnvironmentObject private var feedStore: FeedStore
    let path: String
    let contentMode: ContentMode

    var body: some View {
        Group {
            if path.hasPrefix("asset:") {
                Image(String(path.dropFirst("asset:".count)))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let data = feedStore.photoData[path], let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    AppTheme.surface
                    ProgressView().tint(AppTheme.primary)
                }
                .task(id: path) { await feedStore.loadPhoto(path: path) }
            }
        }
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
    let editingItem: FeedItem?
    @State private var title: String
    @State private var details: String
    @State private var selectedRecipe: Recipe?
    @State private var existingPhotoPaths: [String]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var showRecipePicker = false
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(editing item: FeedItem? = nil) {
        editingItem = item
        _title = State(initialValue: item?.post.title ?? "")
        _details = State(initialValue: item?.post.body ?? "")
        _selectedRecipe = State(initialValue: item?.recipe)
        _existingPhotoPaths = State(initialValue: item?.post.photoPaths ?? [])
    }

    private var photoCount: Int { existingPhotoPaths.count + photos.count }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photoCount <= 4
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
                        ZStack(alignment: .topTrailing) {
                            Button { showRecipePicker = true } label: {
                                RecipeSelectionCard(recipe: selectedRecipe)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) { self.selectedRecipe = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .accessibilityLabel("Remove linked recipe")
                        }
                    } else {
                        Button { showRecipePicker = true } label: {
                            composerActionLabel("Add Recipe", systemImage: "fork.knife")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    if photoCount < 4 {
                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: 4 - existingPhotoPaths.count,
                            matching: .images
                        ) {
                            composerActionLabel(
                                photoCount == 0 ? "Add Photos" : "Add More Photos",
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if photoCount > 0 {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(existingPhotoPaths.enumerated()), id: \.element) { index, path in
                                ZStack(alignment: .topTrailing) {
                                    PostPhoto(path: path)
                                        .frame(height: 110)
                                    removeButton(label: "Remove existing photo \(index + 1)") {
                                        existingPhotoPaths.removeAll { $0 == path }
                                    }
                                }
                            }

                            ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                                if let image = UIImage(data: data) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 110)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        removeButton(label: "Remove new photo \(index + 1)") {
                                            removePhoto(at: index)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Photos")
                        Spacer()
                        Text("\(photoCount)/4")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(editingItem == nil ? "New Post" : "Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .disabled(isPublishing)
                        .accessibilityLabel("Close post composer")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingItem == nil ? "Publish" : "Save", action: publish)
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
                        ProgressView(editingItem == nil ? "Publishing…" : "Saving…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func composerActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppTheme.primary)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.7))
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel(label)
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
                if let editingItem {
                    try await feedStore.update(
                        post: editingItem.post,
                        title: title,
                        body: details,
                        recipe: selectedRecipe,
                        retainedPhotoPaths: existingPhotoPaths,
                        newPhotos: photos
                    )
                } else {
                    try await feedStore.publish(title: title, body: details, recipe: selectedRecipe, photos: photos)
                }
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
    @State private var selectedTag: String?

    private var tags: [String] { Array(Set(mealStore.recipes.flatMap(\.tags))).sorted() }

    private var filteredRecipes: [Recipe] {
        mealStore.recipes.filter { recipe in
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty
                || recipe.title.localizedCaseInsensitiveContains(query)
                || recipe.author.localizedCaseInsensitiveContains(query)
                || recipe.ingredients.contains { $0.display.localizedCaseInsensitiveContains(query) }
            return matchesQuery && (selectedTag == nil || recipe.tags.contains(selectedTag!))
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
                        Text("Add Recipe")
                            .font(.custom("Plus Jakarta Sans", size: 28).weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(AppTheme.text)
                                .frame(width: 30, height: 30)
                        }
                    }
                    Text("Choose a recipe to link to this post")
                        .font(.custom("Inter", size: 12))
                        .foregroundStyle(AppTheme.label)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label)
                            TextField("Search", text: $query).foregroundStyle(AppTheme.text)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(AppTheme.input)
                        .clipShape(Capsule())

                        Menu {
                            Button("All Labels") { selectedTag = nil }
                            ForEach(tags, id: \.self) { tag in Button(tag) { selectedTag = tag } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedTag ?? "Label")
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .font(.custom("Inter", size: 14))
                            .foregroundStyle(AppTheme.label)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(AppTheme.input)
                            .clipShape(Capsule())
                        }
                    }

                    ScrollView {
                        LazyVStack(spacing: 9) {
                            if filteredRecipes.isEmpty {
                                Text("No recipes found")
                                    .font(.custom("Inter", size: 14))
                                    .foregroundStyle(AppTheme.label)
                                    .padding(.top, 30)
                            } else {
                                ForEach(filteredRecipes) { recipe in
                                    Button {
                                        selectedRecipe = recipe
                                        dismiss()
                                    } label: {
                                        RecipeSelectionCard(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 1)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
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
