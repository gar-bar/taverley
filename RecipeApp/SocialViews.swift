import SwiftUI

struct SocialCountsView: View {
    @EnvironmentObject private var socialStore: SocialStore
    let profileID: UUID

    private var relationship: ProfileRelationship {
        socialStore.relationships[profileID] ?? ProfileRelationship(isFollowing: false, followerCount: 0, followingCount: 0)
    }

    var body: some View {
        HStack(spacing: 28) {
            NavigationLink {
                RelationshipListView(profileID: profileID, kind: .followers)
            } label: {
                countLabel(value: relationship.followerCount, title: "Followers")
            }
            NavigationLink {
                RelationshipListView(profileID: profileID, kind: .following)
            } label: {
                countLabel(value: relationship.followingCount, title: "Following")
            }
        }
        .buttonStyle(.plain)
        .task { await socialStore.loadRelationship(for: profileID) }
    }

    private func countLabel(value: Int, title: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.headline).foregroundStyle(AppTheme.text)
            Text(title).font(.caption).foregroundStyle(AppTheme.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(title.lowercased())")
    }
}

struct SocialPersonRow: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var feedStore: FeedStore
    let summary: SocialProfileSummary
    var showsFollowButton = true
    @State private var errorMessage: String?
    @State private var showCancelConfirmation = false

    private var relationship: ProfileRelationship {
        socialStore.relationships[summary.id] ?? summary.relationship
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                PublicProfileView(profileID: summary.id)
            } label: {
                HStack(spacing: 12) {
                    InitialsAvatar(profile: summary.profile, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(summary.profile.username)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text("\(relationship.followerCount) followers")
                            .font(.caption)
                            .foregroundStyle(AppTheme.label)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if showsFollowButton, socialStore.currentUserID != summary.id {
                Button(followButtonTitle) { followButtonTapped() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle((relationship.isFollowing || relationship.isRequested) ? AppTheme.text : .black)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background((relationship.isFollowing || relationship.isRequested) ? AppTheme.input : AppTheme.primary)
                    .clipShape(Capsule())
                    // SocialPersonRow is used inside SwiftUI Lists. Without an
                    // explicit borderless style, a row/navigation tap can also
                    // dispatch this button's action and create a follow.
                    .buttonStyle(.borderless)
                    .disabled(socialStore.pendingFollowIDs.contains(summary.id))
            }
        }
        .padding(.vertical, 7)
        .alert("Couldn’t update follow", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Please try again.") }
        .confirmationDialog(
            relationship.isRequested ? "Cancel follow request?" : "Unfollow @\(summary.profile.username)?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(relationship.isRequested ? "Cancel request" : "Unfollow", role: .destructive) { toggleFollow() }
            Button("Keep following", role: .cancel) { }
        }
    }

    private func toggleFollow() {
        Task {
            do {
                try await socialStore.toggleFollow(profileID: summary.id)
                try await feedStore.refresh()
                await feedStore.refreshCurrentProfile()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func followButtonTapped() {
        if relationship.isFollowing || relationship.isRequested { showCancelConfirmation = true }
        else { toggleFollow() }
    }

    private var followButtonTitle: String {
        relationship.isFollowing ? "Following" : (relationship.isRequested ? "Requested" : "Follow")
    }
}

struct RelationshipListView: View {
    @EnvironmentObject private var socialStore: SocialStore
    let profileID: UUID
    let kind: SocialListKind
    @State private var query = ""

    private var page: SocialPage<SocialProfileSummary> {
        socialStore.page(profileID: profileID, kind: kind, query: query)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if page.items.isEmpty && page.isLoading {
                ProgressView("Loading \(kind.rawValue)…").tint(AppTheme.primary)
            } else if page.items.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No \(kind.rawValue) yet" : "No matching people",
                    systemImage: "person.2",
                    description: Text(query.isEmpty ? "People will appear here when the relationship is created." : "Try another username.")
                )
            } else {
                List {
                    ForEach(page.items) { person in
                        SocialPersonRow(summary: person)
                            .listRowBackground(AppTheme.background)
                            .listRowSeparatorTint(AppTheme.border)
                            .onAppear {
                                if person.id == page.items.last?.id, page.hasMore {
                                    Task { await socialStore.loadPeople(profileID: profileID, kind: kind, query: query) }
                                }
                            }
                    }
                    if page.isLoading { ProgressView().frame(maxWidth: .infinity).listRowBackground(AppTheme.background) }
                    if let error = page.errorMessage {
                        Button("Retry: \(error)") { Task { await load(reset: page.items.isEmpty) } }
                            .font(.caption).foregroundStyle(AppTheme.primary)
                            .listRowBackground(AppTheme.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(kind == .followers ? "Followers" : "Following")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search usernames")
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(reset: true)
        }
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        await socialStore.loadPeople(profileID: profileID, kind: kind, query: query, reset: reset)
    }
}

struct PublicProfileView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var feedStore: FeedStore
    let profileID: UUID
    @State private var selectedPost: FeedItem?
    @State private var followError: String?
    @State private var showCancelConfirmation = false

    private var content: PublicProfileContent? { socialStore.profileContent[profileID] }
    private var relationship: ProfileRelationship {
        socialStore.relationships[profileID] ?? ProfileRelationship(isFollowing: false, followerCount: 0, followingCount: 0)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if let content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        profileHeader(content.profile)
                        if canViewContent {
                            if !content.recipes.isEmpty { sharedRecipes(content.recipes) }
                            Text("Posts \(content.posts.count)")
                                .font(.custom("Plus Jakarta Sans", size: 26).weight(.bold))
                                .padding(.horizontal, 16)
                            if content.posts.isEmpty {
                                ContentUnavailableView("No posts yet", systemImage: "text.bubble")
                                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(content.posts) { post in
                                        FeedPostCard(item: post) { selectedPost = post }
                                        Divider().overlay(AppTheme.border).padding(.horizontal, 16)
                                    }
                                }
                            }
                        } else {
                            privateContentNotice
                        }
                    }
                    .padding(.bottom, 32)
                }
                .refreshable { await socialStore.loadProfile(profileID, refresh: true) }
            } else if socialStore.loadingProfiles.contains(profileID) {
                ProgressView("Loading profile…").tint(AppTheme.primary)
            } else {
                ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .navigationTitle(content.map { "@\($0.profile.username)" } ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPost) { PostDetailView(item: $0) }
        .task { await socialStore.loadProfile(profileID) }
        .alert("Couldn’t update follow", isPresented: Binding(
            get: { followError != nil }, set: { if !$0 { followError = nil } }
        )) { Button("OK") { followError = nil } } message: { Text(followError ?? "Please try again.") }
        .confirmationDialog(
            relationship.isRequested ? "Cancel follow request?" : "Unfollow @\(content?.profile.username ?? "this person")?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(relationship.isRequested ? "Cancel request" : "Unfollow", role: .destructive) { toggleFollow() }
            Button("Keep following", role: .cancel) { }
        }
    }

    private func profileHeader(_ profile: UserProfile) -> some View {
        VStack(spacing: 15) {
            InitialsAvatar(profile: profile, size: 88)
            Text("@\(profile.username)")
                .font(.custom("Plus Jakarta Sans", size: 28).weight(.bold))
                .foregroundStyle(AppTheme.text)
            if profile.isPrivate {
                Label("Private account", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.label)
            }
            SocialCountsView(profileID: profileID)
            if socialStore.currentUserID != profileID {
                Button(followButtonTitle) { followButtonTapped() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle((relationship.isFollowing || relationship.isRequested) ? AppTheme.text : .black)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background((relationship.isFollowing || relationship.isRequested) ? AppTheme.input : AppTheme.primary)
                    .clipShape(Capsule())
                    .disabled(socialStore.pendingFollowIDs.contains(profileID))
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func sharedRecipes(_ recipes: [Recipe]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared Recipes \(recipes.count)")
                .font(.custom("Plus Jakarta Sans", size: 24).weight(.bold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(recipes) { recipe in
                        NavigationLink { RecipeDetailView(recipe: recipe) } label: { RecipeCard(recipe: recipe).frame(width: 176) }
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
        }
    }

    private func toggleFollow() {
        Task {
            do {
                try await socialStore.toggleFollow(profileID: profileID)
                try await feedStore.refresh()
                await feedStore.refreshCurrentProfile()
            } catch { followError = error.localizedDescription }
        }
    }

    private func followButtonTapped() {
        if relationship.isFollowing || relationship.isRequested { showCancelConfirmation = true }
        else { toggleFollow() }
    }

    private var canViewContent: Bool {
        guard let content else { return false }
        return !content.profile.isPrivate || socialStore.currentUserID == profileID || relationship.isFollowing
    }

    private var followButtonTitle: String {
        relationship.isFollowing ? "Following" : (relationship.isRequested ? "Requested" : "Follow")
    }

    private var privateContentNotice: some View {
        ContentUnavailableView {
            Label("This account is private", systemImage: "lock.fill")
        } description: {
            Text(relationship.isRequested ? "Your follow request is waiting for approval." : "Follow this account to see its posts and shared recipes after your request is approved.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var isPrivate = false
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Private account", isOn: $isPrivate)
                        .tint(AppTheme.primary)
                        .disabled(isSaving)
                } footer: {
                    Text("Private accounts can still be found by username and anyone can view their followers and following. Only approved followers can view your posts and shared recipes. Your household is never shown on your public profile.")
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task {
                isPrivate = feedStore.currentProfile?.isPrivate ?? false
                hasLoaded = true
            }
            .onChange(of: isPrivate) { _, value in if hasLoaded { save(value) } }
            .alert("Couldn’t update privacy", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
    }

    private func save(_ value: Bool) {
        guard !isSaving else { return }
        let previous = !value
        Task {
            isSaving = true
            do {
                try await feedStore.setProfilePrivacy(isPrivate: value)
            } catch {
                isPrivate = previous
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct FollowRequestNotificationButton: View {
    @EnvironmentObject private var socialStore: SocialStore

    var body: some View {
        NavigationLink { FollowRequestInboxView() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: socialStore.followRequests.isEmpty ? "person.badge.clock" : "person.badge.clock.fill")
                    .frame(width: 44, height: 44)
                if !socialStore.followRequests.isEmpty {
                    Text("\(min(socialStore.followRequests.count, 9))")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 16, height: 16).background(AppTheme.primary).clipShape(Circle())
                        .offset(x: -2, y: 2)
                }
            }
        }
        .accessibilityLabel("Follow requests, \(socialStore.followRequests.count) pending")
    }
}

/// The Feed has one notification destination for every pending social and
/// household action, rather than competing toolbar badges.
struct NotificationsButton: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var householdStore: HouseholdStore

    private var pendingCount: Int {
        socialStore.followRequests.count + householdStore.pendingInvitationCount
    }

    var body: some View {
        NavigationLink { NotificationsInboxView() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: pendingCount > 0 ? "bell.fill" : "bell")
                    .frame(width: 44, height: 44)
                if pendingCount > 0 {
                    Text("\(min(pendingCount, 9))")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 16, height: 16).background(AppTheme.primary).clipShape(Circle())
                        .offset(x: -2, y: 2)
                }
            }
        }
        .accessibilityLabel("Notifications, \(pendingCount) pending")
    }
}

struct NotificationsInboxView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var householdStore: HouseholdStore

    private var hasNotifications: Bool {
        !socialStore.followRequests.isEmpty || householdStore.pendingInvitationCount > 0
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if hasNotifications {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !socialStore.followRequests.isEmpty {
                            notificationLink(
                                title: "Follow requests",
                                detail: "\(socialStore.followRequests.count) pending",
                                image: "person.badge.clock",
                                destination: { FollowRequestInboxView() }
                            )
                        }
                        if householdStore.pendingInvitationCount > 0 {
                            notificationLink(
                                title: "Household invitations",
                                detail: "\(householdStore.pendingInvitationCount) pending",
                                image: "house.fill",
                                destination: { HouseholdInvitationInboxView() }
                            )
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await socialStore.refreshFollowRequests()
                    await householdStore.refreshInvitations()
                }
            } else {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Follow requests and household invitations will appear here."))
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await socialStore.refreshFollowRequests()
            await householdStore.refreshInvitations()
        }
    }

    private func notificationLink<Destination: View>(title: String, detail: String, image: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            SurfaceCard {
                HStack(spacing: 12) {
                    Image(systemName: image)
                        .font(.title3).foregroundStyle(AppTheme.primary)
                        .frame(width: 42, height: 42).background(AppTheme.input).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline).foregroundStyle(AppTheme.text)
                        Text(detail).font(.caption).foregroundStyle(AppTheme.label)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.label)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct FollowRequestInboxView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var feedStore: FeedStore
    @State private var workingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if socialStore.followRequests.isEmpty {
                ContentUnavailableView("No follow requests", systemImage: "person.badge.clock", description: Text("Requests to follow your private account will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(socialStore.followRequests) { request in requestCard(request) }
                    }
                    .padding(16)
                }
                .refreshable { await socialStore.refreshFollowRequests() }
            }
        }
        .navigationTitle("Follow requests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await socialStore.refreshFollowRequests() }
        .alert("Couldn’t update request", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func requestCard(_ request: FollowRequest) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                NavigationLink { PublicProfileView(profileID: request.id) } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(profile: request.requester, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("@\(request.requester.username)").font(.headline).foregroundStyle(AppTheme.text)
                            Text("Requested \(request.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(AppTheme.label)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 8) {
                    Button("Approve") { respond(request, approve: true) }
                        .buttonStyle(.borderedProminent).tint(AppTheme.primary).foregroundStyle(.black)
                    Button("Decline") { respond(request, approve: false) }
                        .buttonStyle(.bordered).tint(AppTheme.label)
                }
                .font(.caption.weight(.semibold))
                .disabled(workingID != nil)
            }
        }
    }

    private func respond(_ request: FollowRequest, approve: Bool) {
        Task {
            workingID = request.id
            do {
                try await socialStore.respondToFollowRequest(request, approve: approve)
                try? await feedStore.refresh()
            } catch { errorMessage = error.localizedDescription }
            workingID = nil
        }
    }
}
