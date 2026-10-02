import SwiftUI
import PhotosUI
import UIKit
import Foundation

enum AppTab: Hashable {
    case feed, recipes, plans, calendar, profile
}

struct RootView: View {
    @State private var tab: AppTab = .feed

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Feed", image: "IconlyChat") }
                .tag(AppTab.feed)
            RecipeLibraryView()
                .tabItem { Label("Recipes", image: "FigmaNavDocument") }
                .tag(AppTab.recipes)
            MealPlanListView()
                .tabItem { Label("Plans", image: "FigmaNavFolder") }
                .tag(AppTab.plans)
            CalendarView()
                .tabItem { Label("Calendar", image: "FigmaNavCalendar") }
                .tag(AppTab.calendar)
            ProfileView()
                .tabItem { Label("Profile", image: "FigmaNavProfile") }
                .tag(AppTab.profile)
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}

struct PlaceholderView: View { let title: String; let detail: String; var body: some View { ZStack { AppTheme.background.ignoresSafeArea(); ContentUnavailableView(title, systemImage: "fork.knife", description: Text(detail)) } } }

struct AuthenticationGate: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var householdStore: HouseholdStore

    var body: some View {
        Group {
            if authentication.isRestoring {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    ProgressView().tint(AppTheme.primary)
                }
            } else if authentication.isSkippingForNow {
                RootView()
                    .onAppear { feedStore.deactivateAccount(); socialStore.deactivateAccount(); householdStore.deactivateAccount() }
            } else if let session = authentication.session, let dataClient = authentication.dataClient {
                RootView()
                    .task(id: session.accessToken) {
                        await store.activateAccount(session, client: dataClient)
                        await feedStore.activateAccount(session, client: dataClient)
                        await socialStore.activateAccount(session, client: dataClient)
                        await householdStore.activateAccount(session, client: dataClient)
                    }
            } else {
                EmailCodeSignInView()
                    .onAppear {
                        store.deactivateAccount()
                        feedStore.deactivateAccount()
                        socialStore.deactivateAccount()
                        householdStore.deactivateAccount()
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EmailCodeSignInView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var mode: AuthEntryMode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var showsPassword = false
    @State private var showsConfirmation = false
    @FocusState private var focusedField: Field?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var usernameStatus: UsernameAvailability = .idle

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if authentication.pendingKind != nil {
                AuthCodeVerificationView {
                    email = authentication.pendingEmail ?? email
                    mode = .signIn
                    passwordConfirmation = ""
                    authentication.cancelPendingFlow()
                }
            } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 64)

                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(AppTheme.primary)

                    Text(mode.title)
                        .font(.custom("Plus Jakarta Sans", size: 31).weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .padding(.top, 24)

                    Text(mode.detail)
                        .font(.custom("Inter", size: 16))
                        .foregroundStyle(AppTheme.label)
                        .lineSpacing(3)
                        .padding(.top, 10)

                    if mode == .createAccount {
                        fieldLabel("Username", top: 28)
                        TextField("your_username", text: $username)
                            .figmaInput().textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.username).focused($focusedField, equals: .username).submitLabel(.next)
                            .onSubmit { focusedField = .email }
                            .onChange(of: username) { username = UsernamePolicy.normalize(username) }
                            .task(id: username) { await checkUsername() }
                        usernameAvailabilityLabel
                    }

                    fieldLabel("Email address", top: mode == .createAccount ? 16 : 30)

                    TextField("you@example.com", text: $email)
                        .figmaInput()
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .padding(.top, 8)

                    fieldLabel("Password", top: 18)
                    passwordField("Password", text: $password, contentType: mode == .createAccount ? .newPassword : .password, revealsText: $showsPassword)
                        .padding(.top, 8)
                        .focused($focusedField, equals: .password)

                    if mode == .createAccount {
                        fieldLabel("Confirm password", top: 18)
                        passwordField("Confirm password", text: $passwordConfirmation, contentType: .newPassword, revealsText: $showsConfirmation)
                            .padding(.top, 8)
                            .focused($focusedField, equals: .confirmation)
                        PasswordRequirementsView(password: password, confirmation: passwordConfirmation)
                            .padding(.top, 12)
                    }

                    Button(action: submit) { buttonLabel(mode.buttonTitle) }
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.top, 14)

                    if let errorMessage {
                        InlineErrorBanner(message: errorMessage, retry: nil).padding(.top, 16)
                    }

                    if mode == .signIn {
                        Button("Forgot password?") { mode = .recovery; resetMessages() }
                            .authSecondaryButton()
                    }

                    Button(mode.switchTitle) {
                        mode = mode.switchMode
                        password = ""; passwordConfirmation = ""; resetMessages()
                    }
                    .authSecondaryButton()

                    #if DEBUG
                    Button("Skip for now") { authentication.isSkippingForNow = true }
                        .authSecondaryButton()
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                }
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let validEmail = trimmed.contains("@") && trimmed.split(separator: "@").last?.contains(".") == true
        switch mode {
        case .signIn: return validEmail && !password.isEmpty
        case .recovery: return validEmail
        case .createAccount:
            return validEmail && UsernamePolicy.isValid(username) && usernameStatus == .available
                && PasswordPolicy.isValid(password) && password == passwordConfirmation
        }
    }

    private func fieldLabel(_ title: String, top: CGFloat) -> some View {
        Text(title).font(.custom("Inter", size: 15).weight(.medium)).foregroundStyle(AppTheme.text).padding(.top, top)
    }

    private func passwordField(_ title: String, text: Binding<String>, contentType: UITextContentType, revealsText: Binding<Bool>) -> some View {
        HStack {
            Group {
                if revealsText.wrappedValue { TextField(title, text: text) } else { SecureField(title, text: text) }
            }
            .textContentType(contentType)
            Button { revealsText.wrappedValue.toggle() } label: { Image(systemName: revealsText.wrappedValue ? "eye.slash" : "eye") }
                .accessibilityLabel(revealsText.wrappedValue ? "Hide \(title)" : "Show \(title)")
        }.figmaInput()
    }

    @ViewBuilder private var usernameAvailabilityLabel: some View {
        switch usernameStatus {
        case .checking: Text("Checking availability…").foregroundStyle(AppTheme.label)
        case .available: Label("Username available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken: Label("Username already taken", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .failed: Text("Availability could not be checked.").foregroundStyle(.red)
        case .idle: Text("3–30 lowercase letters, numbers, periods, or underscores.").foregroundStyle(AppTheme.label)
        }
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

    private func submit() {
        Task {
            isSubmitting = true
            errorMessage = nil
            do {
                email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch mode {
                case .signIn: try await authentication.signIn(email: email, password: password)
                case .createAccount: try await authentication.signUp(username: username, email: email, password: password, confirmation: passwordConfirmation)
                case .recovery: try await authentication.requestPasswordRecovery(email: email)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func checkUsername() async {
        guard mode == .createAccount, UsernamePolicy.isValid(username) else { usernameStatus = .idle; return }
        usernameStatus = .checking
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do { usernameStatus = try await authentication.checkUsernameAvailability(username) ? .available : .taken }
        catch { usernameStatus = .failed }
    }

    private func resetMessages() { errorMessage = nil; usernameStatus = .idle }

    private enum Field { case username, email, password, confirmation }
}

private enum AuthEntryMode {
    case signIn, createAccount, recovery
    var title: String { switch self { case .signIn: "Welcome to Taverley"; case .createAccount: "Create your account"; case .recovery: "Reset your password" } }
    var detail: String { switch self { case .signIn: "Sign in to keep your recipes available on every device."; case .createAccount: "Choose your unique identity and secure your recipes."; case .recovery: "We’ll email you a six-digit recovery code." } }
    var buttonTitle: String { switch self { case .signIn: "Sign in"; case .createAccount: "Create account"; case .recovery: "Send recovery code" } }
    var switchTitle: String { switch self { case .signIn: "Create an account"; case .createAccount, .recovery: "Back to sign in" } }
    var switchMode: Self { self == .signIn ? .createAccount : .signIn }
}

private enum UsernameAvailability { case idle, checking, available, taken, failed }

private struct PasswordRequirementsView: View {
    let password: String
    let confirmation: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirement("12 or more characters", met: PasswordPolicy.hasMinimumLength(password))
            requirement("At least one number", met: PasswordPolicy.hasNumber(password))
            requirement("At least one symbol", met: PasswordPolicy.hasSymbol(password))
            requirement("Passwords match", met: !confirmation.isEmpty && password == confirmation)
        }
    }
    private func requirement(_ text: String, met: Bool) -> some View {
        Label(text, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.custom("Inter", size: 13)).foregroundStyle(met ? .green : AppTheme.label)
    }
}

private struct AuthCodeVerificationView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    let onUseConfirmationLink: () -> Void
    @State private var code = ""
    @State private var replacementUsername = ""
    @State private var needsUsername = false
    @State private var recoveryVerified = false
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resendSeconds = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 70)
                Image(systemName: recoveryVerified ? "lock.rotation" : "envelope.badge")
                    .font(.system(size: 48)).foregroundStyle(AppTheme.primary)
                Text(recoveryVerified ? "Choose a new password" : "Check your email")
                    .font(.custom("Plus Jakarta Sans", size: 31).weight(.bold)).foregroundStyle(AppTheme.text)

                if recoveryVerified {
                    SecureField("New password", text: $newPassword).figmaInput().textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmation).figmaInput().textContentType(.newPassword)
                    PasswordRequirementsView(password: newPassword, confirmation: confirmation)
                    primaryButton("Save new password", disabled: !PasswordPolicy.isValid(newPassword) || newPassword != confirmation) { finishRecovery() }
                } else if needsUsername {
                    Text("Your original username was just claimed. Choose another to finish creating your account.").foregroundStyle(AppTheme.label)
                    TextField("Username", text: $replacementUsername).figmaInput().textInputAutocapitalization(.never).autocorrectionDisabled()
                    primaryButton("Finish account", disabled: !UsernamePolicy.isValid(replacementUsername)) { claimUsername() }
                } else {
                    Text(verificationInstructions)
                        .font(.custom("Inter", size: 16)).foregroundStyle(AppTheme.label)
                    TextField("000000", text: $code)
                        .figmaInput().keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .onChange(of: code) { code = String(code.filter(\.isNumber).prefix(6)) }
                    primaryButton("Verify code", disabled: code.count != 6) { verify() }
                    Button(resendSeconds > 0 ? "Resend in \(resendSeconds)s" : "Resend email") { resend() }
                        .disabled(resendSeconds > 0).authSecondaryButton()
                    if authentication.pendingKind == .signup {
                        Button("I confirmed using the email link") { onUseConfirmationLink() }
                            .authSecondaryButton()
                    }
                    Button("Use a different email") { authentication.cancelPendingFlow() }.authSecondaryButton()
                }

                if let errorMessage { Text(errorMessage).font(.custom("Inter", size: 14)).foregroundStyle(.red) }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .task(id: resendSeconds) {
            guard resendSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { resendSeconds -= 1 }
        }
    }

    private var maskedEmail: String {
        guard let email = authentication.pendingEmail, let at = email.firstIndex(of: "@") else { return "your email" }
        let name = email[..<at]
        return "\(name.prefix(1))•••\(email[at...])"
    }

    private var verificationInstructions: String {
        if authentication.pendingKind == .signup {
            return "Open the email sent to \(maskedEmail). Enter its six-digit code, or use its confirmation link and then return here."
        }
        return "Enter the six-digit recovery code sent to \(maskedEmail)."
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { if isSubmitting { ProgressView().tint(.black) }; Text(title) }.frame(maxWidth: .infinity).frame(height: 48) }
            .font(.custom("Inter", size: 16).weight(.bold)).foregroundStyle(.black).background(AppTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14)).disabled(disabled || isSubmitting)
    }

    private func verify() { run { try await authentication.verifyPendingCode(code); if authentication.pendingKind == .recovery { recoveryVerified = true } } }
    private func finishRecovery() { run { try await authentication.finishPasswordRecovery(password: newPassword, confirmation: confirmation) } }
    private func claimUsername() { run { do { try await authentication.claimPendingUsername(replacementUsername) } catch AuthenticationError.usernameTaken { needsUsername = true; throw AuthenticationError.usernameTaken } } }
    private func resend() { run { try await authentication.resendPendingCode(); resendSeconds = 60 } }
    private func run(_ operation: @escaping () async throws -> Void) {
        Task { isSubmitting = true; errorMessage = nil; do { try await operation() } catch AuthenticationError.usernameTaken { needsUsername = true; errorMessage = AuthenticationError.usernameTaken.localizedDescription } catch { errorMessage = error.localizedDescription }; isSubmitting = false }
    }
}

private extension View {
    func authSecondaryButton() -> some View {
        font(.custom("Inter", size: 16).weight(.semibold)).foregroundStyle(AppTheme.primary).frame(maxWidth: .infinity).padding(.top, 10)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var selectedPostID: UUID?

    private var featuredRecipes: [Recipe] {
        Array(store.recipes.sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }
    private var authoredPosts: [FeedItem] {
        guard let userID = feedStore.currentProfile?.id ?? feedStore.currentUserID else { return [] }
        return feedStore.items.filter { $0.post.authorID == userID }
    }
    private var featuredPosts: [FeedItem] { Array(authoredPosts.prefix(5)) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 28) {
                        InitialsAvatar(profile: feedStore.currentProfile ?? UserProfile(id: UUID(), displayName: "Taverley", username: "taverley"), size: 96)

                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feedStore.currentProfile?.username ?? "Garnet")
                                    .font(.custom("Plus Jakarta Sans", size: 34).weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                            }

                            Text("Your recipes, plans, and shared meals")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.label)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 30)

                    if let profileID = feedStore.currentProfile?.id ?? feedStore.currentUserID {
                        SocialCountsView(profileID: profileID)
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                    }

                    HouseholdProfileCard()
                        .padding(.horizontal, 24)
                        .padding(.top, 28)

                    NavigationLink {
                        ProfileRecipesView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("Recipes")
                                .font(.custom("Plus Jakarta Sans", size: 30).weight(.bold))
                            Text("\(store.recipes.count)")
                                .font(.custom("Inter", size: 28))
                                .foregroundStyle(AppTheme.label)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.label)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all \(store.recipes.count) recipes")
                    .foregroundStyle(AppTheme.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

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

                    NavigationLink {
                        ProfilePostsView()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("Posts")
                                .font(.custom("Plus Jakarta Sans", size: 30).weight(.bold))
                            Text("\(authoredPosts.count)")
                                .font(.custom("Inter", size: 28))
                                .foregroundStyle(AppTheme.label)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.label)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all \(authoredPosts.count) posts")
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
                            ForEach(featuredPosts) { post in
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
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { MyFavouritesView() } label: { Image(systemName: "star") }
                    .accessibilityLabel("My favourites")
                NavigationLink { ProfileSettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Profile settings")
            }
        }
        .navigationDestination(item: $selectedPostID) { postID in
            PostDetailView(postID: postID)
        }
        }
    }
}

private enum MeasurementPreference: String, CaseIterable, Identifiable {
    case metric = "Metric"
    case imperial = "Imperial"
    var id: String { rawValue }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @EnvironmentObject private var feedStore: FeedStore
    @AppStorage("measurement-preference") private var measurement = MeasurementPreference.metric.rawValue
    @State private var displayName = ""
    @State private var savedDisplayName = ""
    @State private var isPrivate = false
    @State private var isSavingName = false
    @State private var isSavingPrivacy = false
    @State private var hasLoaded = false
    @State private var showBugReport = false
    @State private var showDeleteAccount = false
    @State private var showSignOutConfirmation = false
    @State private var errorMessage: String?
    @FocusState private var isDisplayNameFocused: Bool

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                settingsCard("Preferences") {
                    settingRow("Display Name") {
                        HStack(spacing: 8) {
                            TextField("Display name", text: $displayName)
                                .multilineTextAlignment(.leading)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isDisplayNameFocused)
                                .onSubmit { saveDisplayName() }
                            if isSavingName { ProgressView().controlSize(.small) }
                        }
                        .settingsValueStyle()
                    }

                    settingRow("Private Account") {
                        Toggle("Private Account", isOn: $isPrivate)
                            .labelsHidden()
                            .tint(AppTheme.accent)
                            .disabled(isSavingPrivacy || !hasLoaded)
                    }

                    settingRow("Measuring Unit") {
                        Picker("Measuring Unit", selection: $measurement) {
                            ForEach(MeasurementPreference.allCases) { preference in
                                Text(preference.rawValue).tag(preference.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(AppTheme.textSecondary)
                        .settingsValueStyle()
                    }
                }

                settingsCard("Feedback") {
                    Button { showBugReport = true } label: {
                        HStack {
                            Text("Bug Report")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens a form to submit a bug report")
                }

                settingsCard("About") {
                    settingRow("Version") {
                        Text(version).settingsValueStyle()
                    }
                }

                Button("Sign Out") { showSignOutConfirmation = true }
                    .settingsActionStyle(foreground: AppTheme.accent)
                    .confirmationDialog("Sign out of Taverley?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { authentication.signOut() }
                        Button("Cancel", role: .cancel) { }
                    }

                Button("Delete Account", role: .destructive) { showDeleteAccount = true }
                    .settingsActionStyle(foreground: AppTheme.destructive)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            guard !hasLoaded else { return }
            let profile = feedStore.currentProfile
            displayName = profile?.displayName ?? ""
            savedDisplayName = displayName
            isPrivate = profile?.isPrivate ?? false
            hasLoaded = true
        }
        .onChange(of: isDisplayNameFocused) { _, focused in
            if !focused { saveDisplayName() }
        }
        .onChange(of: isPrivate) { _, newValue in
            if hasLoaded { savePrivacy(newValue) }
        }
        .sheet(isPresented: $showBugReport) { BugReportView() }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountView() }
        .alert("Couldn’t save settings", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            value().frame(maxWidth: 150, alignment: .trailing)
        }
        .frame(minHeight: 36)
    }

    private func saveDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSavingName, trimmed != savedDisplayName else { return }
        guard !trimmed.isEmpty else {
            displayName = savedDisplayName
            return
        }
        Task {
            isSavingName = true
            do {
                try await feedStore.setDisplayName(trimmed)
                displayName = feedStore.currentProfile?.displayName ?? trimmed
                savedDisplayName = displayName
            } catch {
                displayName = savedDisplayName
                errorMessage = error.localizedDescription
            }
            isSavingName = false
        }
    }

    private func savePrivacy(_ value: Bool) {
        guard !isSavingPrivacy else { return }
        Task {
            isSavingPrivacy = true
            do {
                try await feedStore.setProfilePrivacy(isPrivate: value)
            } catch {
                isPrivate = !value
                errorMessage = error.localizedDescription
            }
            isSavingPrivacy = false
        }
    }
}

private struct SettingsValueStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity)
            .background(AppTheme.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.separator, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsActionStyle: ViewModifier {
    let foreground: Color
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    func settingsValueStyle() -> some View { modifier(SettingsValueStyle()) }
    func settingsActionStyle(foreground: Color) -> some View { modifier(SettingsActionStyle(foreground: foreground)) }
}

private struct BugReportView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    private var canSubmit: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && details.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    TextField("Short title", text: $subject)
                    TextEditor(text: $details)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Tell us what happened and how to reproduce it.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Section {
                    Text("App version \(version) (\(buildNumber)) and your iOS version will be included automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(AppTheme.destructive) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Bug Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }.disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() {
        Task {
            isSubmitting = true
            errorMessage = nil
            do {
                try await feedStore.submitBugReport(subject: subject, details: details, appVersion: version, buildNumber: buildNumber)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

private struct DeleteAccountView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var showFinalConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your profile, recipes, meal plans, calendar data, posts, comments, favourites, and uploaded photos.")
                    Text("If you own a household, ownership transfers to its longest-standing remaining member. A household with no other members is deleted.")
                } header: { Text("Permanent deletion") }

                Section("Confirm your identity") {
                    SecureField("Current password", text: $password).textContentType(.password)
                    TextField("Type DELETE", text: $confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }

                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }

                Section {
                    Button("Delete account", role: .destructive) { showFinalConfirmation = true }
                        .disabled(password.isEmpty || confirmation != "DELETE" || isDeleting)
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .navigationTitle("Delete Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isDeleting) } }
            .alert("Permanently delete your account?", isPresented: $showFinalConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete forever", role: .destructive) { deleteAccount() }
            } message: { Text("This cannot be undone.") }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func deleteAccount() {
        Task {
            isDeleting = true; errorMessage = nil
            do { try await authentication.deleteAccount(password: password); dismiss() }
            catch { errorMessage = error.localizedDescription }
            isDeleting = false
        }
    }
}

private struct MyFavouritesView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var selectedKind: FavouriteKind = .recipes
    @State private var selectedPost: FeedItem?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                favouriteFilter
                    .padding(.horizontal, 16)

                switch selectedKind {
                case .recipes:
                    favouriteRecipes
                case .posts:
                    favouritePosts
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("My Favourites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(item: post)
        }
        .onAppear {
            feedStore.invalidateFavouritePages()
            Task { await feedStore.loadFavouritePage(kind: selectedKind, reset: true) }
        }
        .onChange(of: selectedKind) {
            loadSelectedKindIfNeeded()
        }
    }

    private var favouriteFilter: some View {
        HStack(spacing: 4) {
            ForEach(FavouriteKind.allCases) { kind in
                Button {
                    selectedKind = kind
                } label: {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedKind == kind ? .black : AppTheme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selectedKind == kind ? AppTheme.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedKind == kind ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppTheme.input)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Favourite type")
    }

    @ViewBuilder
    private var favouriteRecipes: some View {
        let state = feedStore.favouriteRecipeState
        if state.items.isEmpty {
            favouriteEmptyState(
                title: "No favourite recipes yet",
                systemImage: "star",
                isLoading: state.isLoading,
                errorMessage: state.errorMessage,
                retry: { Task { await feedStore.loadFavouritePage(kind: .recipes, reset: true) } }
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(state.items) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if recipe.id == state.items.last?.id {
                                Task { await feedStore.loadFavouritePage(kind: .recipes) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                paginationFooter(
                    isLoading: state.isLoading,
                    hasMore: state.hasMore,
                    errorMessage: state.errorMessage,
                    retry: { Task { await feedStore.loadFavouritePage(kind: .recipes) } }
                )
            }
            .scrollIndicators(.hidden)
            .refreshable { await feedStore.loadFavouritePage(kind: .recipes, reset: true) }
        }
    }

    @ViewBuilder
    private var favouritePosts: some View {
        let state = feedStore.favouritePostState
        if state.items.isEmpty {
            favouriteEmptyState(
                title: "No favourite posts yet",
                systemImage: "star",
                isLoading: state.isLoading,
                errorMessage: state.errorMessage,
                retry: { Task { await feedStore.loadFavouritePage(kind: .posts, reset: true) } }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.items) { post in
                        FeedPostCard(item: post) {
                            selectedPost = post
                        }
                        .onAppear {
                            if post.id == state.items.last?.id {
                                Task { await feedStore.loadFavouritePage(kind: .posts) }
                            }
                        }

                        Divider()
                            .overlay(AppTheme.border)
                            .padding(.horizontal, 16)
                    }
                }
                paginationFooter(
                    isLoading: state.isLoading,
                    hasMore: state.hasMore,
                    errorMessage: state.errorMessage,
                    retry: { Task { await feedStore.loadFavouritePage(kind: .posts) } }
                )
            }
            .scrollIndicators(.hidden)
            .refreshable { await feedStore.loadFavouritePage(kind: .posts, reset: true) }
        }
    }

    private func favouriteEmptyState(
        title: String,
        systemImage: String,
        isLoading: Bool,
        errorMessage: String?,
        retry: @escaping () -> Void
    ) -> some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView("Loading favourites…")
                    .tint(AppTheme.primary)
                    .foregroundStyle(AppTheme.label)
                Spacer()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t load favourites", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: retry)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                }
            } else {
                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: Text("Items you star will appear here.")
                )
            }
        }
    }

    private func paginationFooter(
        isLoading: Bool,
        hasMore: Bool,
        errorMessage: String?,
        retry: @escaping () -> Void
    ) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(AppTheme.primary)
                    .padding(.vertical, 24)
            } else if let errorMessage {
                VStack(spacing: 6) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.label)
                        .multilineTextAlignment(.center)
                    Button("Retry loading more", action: retry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                .padding(.vertical, 24)
            } else if !hasMore {
                Text("All favourites loaded")
                    .font(.caption)
                    .foregroundStyle(AppTheme.label)
                    .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadSelectedKindIfNeeded() {
        let shouldLoad = switch selectedKind {
        case .recipes: !feedStore.favouriteRecipeState.hasLoaded
        case .posts: !feedStore.favouritePostState.hasLoaded
        }
        guard shouldLoad else { return }
        Task { await feedStore.loadFavouritePage(kind: selectedKind, reset: true) }
    }
}

private struct ProfilePostsView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @State private var selectedPostID: UUID?

    private var authoredPosts: [FeedItem] {
        guard let userID = feedStore.currentProfile?.id ?? feedStore.currentUserID else { return [] }
        return feedStore.items.filter { $0.post.authorID == userID }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if authoredPosts.isEmpty {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "text.bubble",
                    description: Text("Posts you share will appear here.")
                )
            } else {
                ScrollView {
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
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Posts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedPostID) { postID in
            PostDetailView(postID: postID)
        }
    }
}

private struct ProfileRecipesView: View {
    @EnvironmentObject private var store: MealStore

    private var recipes: [Recipe] {
        store.recipes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if recipes.isEmpty {
                ContentUnavailableView {
                    NavigationEmptyStateLabel(title: "No recipes yet", imageName: "FigmaNavDocument")
                } description: {
                    Text("Your recipes will appear here.")
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(recipes) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                RecipeCard(recipe: recipe)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
                if !recipe.tags.isEmpty { TagPreview(tags: recipe.tags) }
            }
            .frame(width: 162, alignment: .leading)
        }
        .padding(10)
        .frame(width: 278, alignment: .leading)
        .background(AppTheme.background)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recipeImage: some View { RecipeThumbnail(recipe: recipe) }
}


struct LibraryHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTheme.display(.title2))
            .foregroundStyle(AppTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var query = ""; @State private var selectedTags: Set<String> = []; @State private var selectedAuthors: Set<String> = []; @State private var showCreate = false; @State private var newestFirst = true
    private var tags: [String] { RecipeTagPolicy.catalog(from: store.recipes) }
    private var authors: [String] { Array(Set(store.recipes.map(\.author))).sorted() }
    private var filtered: [Recipe] {
        store.recipes.filter { recipe in
            RecipeTagPolicy.matches(recipe, query: query, selectedTags: selectedTags)
                && (selectedAuthors.isEmpty || selectedAuthors.contains(recipe.author))
        }.sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            RecipeTagFilter(title: "Author", selections: $selectedAuthors, options: authors, showsActiveSelections: false)
                            RecipeTagFilter(selections: $selectedTags, options: tags, showsActiveSelections: false)
                        }
                        if !selectedAuthors.isEmpty || !selectedTags.isEmpty {
                            TagFlowLayout {
                                ForEach(selectedAuthors.sorted(), id: \.self) { author in
                                    RemovableTagChip(title: author) { selectedAuthors.remove(author) }
                                }
                                ForEach(selectedTags.sorted(), id: \.self) { tag in
                                    RemovableTagChip(title: tag) { selectedTags.remove(tag) }
                                }
                                Button("Clear all") { selectedAuthors.removeAll(); selectedTags.removeAll() }
                                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xxs)

                    ScrollView {
                        if filtered.isEmpty {
                            ContentUnavailableView {
                                NavigationEmptyStateLabel(title: query.isEmpty && selectedTags.isEmpty && selectedAuthors.isEmpty ? "No recipes yet" : "No matching recipes", imageName: "FigmaNavDocument")
                            } description: {
                                Text(query.isEmpty && selectedTags.isEmpty && selectedAuthors.isEmpty ? "Create your first recipe to start planning meals." : "Try a different search or filter.")
                            } actions: {
                                if query.isEmpty && selectedTags.isEmpty && selectedAuthors.isEmpty {
                                    Button("Create Recipe") { showCreate = true }
                                        .buttonStyle(.borderedProminent)
                                        .tint(AppTheme.primary)
                                        .foregroundStyle(.black)
                                }
                            }
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(filtered) { recipe in NavigationLink { RecipeDetailView(recipe: recipe) } label: { RecipeCard(recipe: recipe) }.buttonStyle(.plain) }
                            }
                            .padding(16)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search recipes")
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create recipe") }
                ToolbarItem(placement: .topBarLeading) {
                    Menu { Button(newestFirst ? "Oldest first" : "Newest first") { newestFirst.toggle() } } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort recipes")
                }
            }
            .sheet(isPresented: $showCreate) { RecipeEditor() }
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    RecipeThumbnail(recipe: recipe)
                        .frame(width: proxy.size.width, height: proxy.size.width * 0.75)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                Text(recipe.title).font(.headline).foregroundStyle(AppTheme.text).lineLimit(1)
                Text("@\(recipe.author)").font(.caption).foregroundStyle(AppTheme.label)
                if !recipe.tags.isEmpty { TagPreview(tags: recipe.tags) }
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.libraryCardContentHeight, maxHeight: AppTheme.Layout.libraryCardContentHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.libraryCardHeight, maxHeight: AppTheme.Layout.libraryCardHeight, alignment: .top)
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject private var store: MealStore; @EnvironmentObject private var feedStore: FeedStore; @EnvironmentObject private var householdStore: HouseholdStore; let recipe: Recipe; var allowsHouseholdSharing = true; @State private var scale = 1.0; @State private var ingredientsOpen = true; @State private var stepsOpen = false; @State private var nutritionOpen = false; @State private var shareMessage: String?; @State private var showEdit = false
    var body: some View { ZStack { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing: 0) {
        ZStack(alignment: .top) {
            Group {
                RecipeThumbnail(recipe: displayedRecipe)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(AppTheme.background.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.coverImage, style: .continuous))
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.xs)
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: AppTheme.Spacing.xs) {
                InitialsAvatar(profile: authorProfile, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(authorUsername).font(.subheadline.weight(.semibold))
                    Text("@\(authorUsername)").font(.caption).foregroundStyle(AppTheme.label)
                }
                Spacer()
                if let totalTime = displayedRecipe.totalTimeMinutes { Label("\(totalTime) min", systemImage: "clock").font(.caption).foregroundStyle(AppTheme.label) }
            }
            Text(displayedRecipe.title).font(AppTheme.display(.title)).foregroundStyle(AppTheme.text)
            Text(displayedRecipe.summary).font(.body).foregroundStyle(AppTheme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            if !displayedRecipe.tags.isEmpty {
                TagFlowLayout { ForEach(displayedRecipe.tags, id: \.self) { Tag(title: $0) } }
            }
            Accordion(title: "Ingredients", isOpen: $ingredientsOpen) { Picker("Scale", selection: $scale) { Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }.pickerStyle(.segmented); ForEach(displayedRecipe.ingredients) { item in Text("• \((item.quantity * scale).formatted(.number.precision(.fractionLength(0...2)))) \(item.unit) \(item.name)").font(.body).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading) } }
            Accordion(title: "Instructions", isOpen: $stepsOpen) { ForEach(Array(displayedRecipe.steps.enumerated()), id: \.element.id) { index, step in Text("\(index + 1). \(step.text)").font(.body).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4) } }
            Accordion(title: "Nutrition Facts", isOpen: $nutritionOpen) { ForEach(displayedRecipe.nutrition) { fact in HStack { Text(fact.name); Spacer(); Text("\(fact.amount.formatted()) \(fact.unit)") }.font(.body).foregroundStyle(AppTheme.text) } }
        }.padding(16).padding(.bottom, 28).background(AppTheme.background).clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)).offset(y: -15)
    } }.scrollIndicators(.hidden) }
        .navigationTitle(displayedRecipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { if allowsHouseholdSharing { Button(feedStore.favouritedRecipeIDs.contains(displayedRecipe.id) ? "Remove from Favourites" : "Add to Favourites", systemImage: "star") { Task { try? await feedStore.toggleRecipeFavourite(recipeID: displayedRecipe.id) } }; Button("Share with Household", systemImage: "house.fill", action: shareRecipe) }; if isPersonalRecipe { Button("Edit Recipe", systemImage: "pencil") { showEdit = true } } } label: { Image(systemName: "ellipsis.circle") } } }
        .sheet(isPresented: $showEdit) { if let currentRecipe = store.recipe(recipe.id) { RecipeEditor(recipe: currentRecipe) } }
        .alert("Household", isPresented: Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(shareMessage ?? "") }
    }

    private var isPersonalRecipe: Bool { store.recipe(recipe.id) != nil }
    private var displayedRecipe: Recipe { store.recipe(recipe.id) ?? recipe }
    private var authorUsername: String {
        let author = displayedRecipe.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.caseInsensitiveCompare("Me") == .orderedSame, let currentProfile = feedStore.currentProfile { return currentProfile.username }
        return author.isEmpty ? "unknown" : author
    }
    private var authorProfile: UserProfile {
        if let member = householdStore.members.first(where: { $0.profile.username == authorUsername }) { return member.profile }
        if let currentProfile = feedStore.currentProfile, currentProfile.username == authorUsername { return currentProfile }
        return UserProfile(id: UUID(), displayName: authorUsername, username: authorUsername)
    }

    private func shareRecipe() {
        guard householdStore.household != nil else { shareMessage = "Create or join a household before sharing recipes."; return }
        Task { do { try await householdStore.share(recipe: displayedRecipe); shareMessage = "Recipe shared with \(householdStore.household?.name ?? "your household")." } catch { shareMessage = error.localizedDescription } }
    }
}

struct Accordion<Content: View>: View { let title: String; @Binding var isOpen: Bool; @ViewBuilder let content: Content; var body: some View { SurfaceCard { VStack(alignment: .leading, spacing: 12) { Button { withAnimation { isOpen.toggle() } } label: { HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); Image(systemName: isOpen ? "chevron.up" : "chevron.down") }.foregroundStyle(AppTheme.text) }; if isOpen { content } } } } }

struct RecipeEditor: View {
    @EnvironmentObject private var store: MealStore; @EnvironmentObject private var feedStore: FeedStore; @Environment(\.dismiss) private var dismiss
    let recipe: Recipe?
    @State private var title: String; @State private var summary: String; @State private var author: String; @State private var servings: Int; @State private var tags: [String]; @State private var ingredients: [Ingredient]; @State private var steps: [RecipeStep]; @State private var nutrition: [NutritionFact]; @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?; @State private var prepMinutes: Int; @State private var cookMinutes: Int; @State private var validationMessage: String?
    @FocusState private var focusedField: RecipeEditorField?

    init(recipe: Recipe? = nil) {
        self.recipe = recipe
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _author = State(initialValue: recipe?.author ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _tags = State(initialValue: RecipeTagPolicy.normalized(recipe?.tags ?? []))
        _ingredients = State(initialValue: recipe?.ingredients ?? [Ingredient(name: "", quantity: 1, unit: "cups")])
        _steps = State(initialValue: recipe?.steps ?? [RecipeStep(text: "")])
        _nutrition = State(initialValue: recipe?.nutrition ?? [])
        _imageData = State(initialValue: recipe?.imageData)
        _prepMinutes = State(initialValue: recipe?.prepTimeMinutes ?? 0)
        _cookMinutes = State(initialValue: recipe?.cookTimeMinutes ?? 0)
    }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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
                    .padding(.bottom, 74)
                }
                .scrollIndicators(.hidden)
                PrimaryButton(title: recipe == nil ? "Save Recipe" : "Save Changes") { saveRecipe() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .background(AppTheme.background.opacity(0.96))
            }
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            imageData = try? await photoItem.loadTransferable(type: Data.self)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var recipeCoverPicker: some View {
        ZStack(alignment: .topLeading) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.42)) }
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
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.coverImage, style: .continuous))
            }
            .buttonStyle(.plain)
            CircularBackButton(action: { dismiss() }).padding(14)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.xs)
    }

    private var recipeForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(recipe == nil ? "Create Recipe" : "Edit Recipe")
                .font(.custom("Plus Jakarta Sans", size: 24).weight(.bold))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recipe details")
                        .font(.custom("Plus Jakarta Sans", size: 19).weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    HStack(spacing: AppTheme.Spacing.xs) {
                        InitialsAvatar(profile: authorProfile, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(resolvedAuthor).font(.subheadline.weight(.semibold))
                            Text("@\(resolvedAuthor)").font(.caption).foregroundStyle(AppTheme.label)
                        }
                    }
                    fieldLabel("Recipe name")
                    TextField("Add title", text: $title).figmaInput().focused($focusedField, equals: .title).onChange(of: title) { retainFocus(.title) }
                    fieldLabel("Description")
                    TextField("Add description", text: $summary, axis: .vertical).lineLimit(3...5).figmaInput().focused($focusedField, equals: .summary).onChange(of: summary) { retainFocus(.summary) }
                    HStack { Text("Serves \(servings)").foregroundStyle(AppTheme.label); Stepper("Servings", value: $servings, in: 1...30).labelsHidden() }
                    RecipeTagEditor(
                        tags: $tags,
                        suggestions: RecipeTagPolicy.catalog(from: store.recipes),
                        titleFont: .custom("Plus Jakarta Sans", size: 19).weight(.bold),
                        usesSurfaceCard: false
                    )
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    fieldLabel("Prep time (minutes)")
                    TextField("0", value: $prepMinutes, format: .number)
                        .keyboardType(.numberPad)
                        .figmaInput()
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    fieldLabel("Cook time (minutes)")
                    TextField("0", value: $cookMinutes, format: .number)
                        .keyboardType(.numberPad)
                        .figmaInput()
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Ingredients").font(.title3.weight(.semibold))
                    HStack(spacing: 8) { Text("Ingredient").frame(maxWidth: .infinity, alignment: .leading); Text("Quantity").frame(maxWidth: .infinity, alignment: .leading); Text("Measure").frame(maxWidth: .infinity, alignment: .leading) }.font(.caption).foregroundStyle(AppTheme.label)
                    ForEach($ingredients) { $ingredient in IngredientInputRow(ingredient: $ingredient) }
                    Button("Add Ingredient", systemImage: "plus") { ingredients.append(Ingredient(name: "", quantity: 1, unit: "")) }.buttonStyle(.bordered).tint(AppTheme.primary)
                }
            }
            SurfaceCard { VStack(alignment: .leading, spacing: 9) { Text("Instructions").font(.title3.weight(.semibold)); ForEach(Array($steps.enumerated()), id: \.element.id) { index, $step in HStack(alignment: .top) { Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 22, height: 22).background(AppTheme.input).clipShape(Circle()); TextField("Add instruction", text: $step.text, axis: .vertical).lineLimit(2...4).figmaInput(); Button(role: .destructive) { steps.remove(at: index) } label: { Image(systemName: "trash") }.disabled(steps.count == 1) } }; Button("Add Step", systemImage: "plus") { steps.append(RecipeStep(text: "")) }.buttonStyle(.bordered).tint(AppTheme.primary) } }
            NutritionFactsEditorCard(nutrition: $nutrition)
            if let validationMessage { InlineErrorBanner(message: validationMessage, retry: nil) }
        }
    }

    private func saveRecipe() {
        let updatedRecipe = Recipe(id: recipe?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, author: resolvedAuthor, servings: servings, tags: RecipeTagPolicy.normalized(tags), ingredients: ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, steps: steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, nutrition: nutrition.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, imageData: imageData, notes: recipe?.notes ?? "", createdAt: recipe?.createdAt ?? Date(), prepTimeMinutes: prepMinutes == 0 ? nil : prepMinutes, cookTimeMinutes: cookMinutes == 0 ? nil : cookMinutes)
        guard !updatedRecipe.title.isEmpty else { validationMessage = "Add a recipe title before saving."; return }
        guard !updatedRecipe.ingredients.isEmpty else { validationMessage = "Add at least one ingredient before saving."; return }
        guard !updatedRecipe.steps.isEmpty else { validationMessage = "Add at least one instruction before saving."; return }
        store.save(recipe: updatedRecipe)
        dismiss()
    }

    private var currentUserName: String { feedStore.currentProfile?.username ?? "Me" }
    private var resolvedAuthor: String {
        let savedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if recipe == nil || savedAuthor.isEmpty || savedAuthor.caseInsensitiveCompare("Me") == .orderedSame { return currentUserName }
        return savedAuthor
    }
    private var authorProfile: UserProfile {
        if let currentProfile = feedStore.currentProfile, currentProfile.username == resolvedAuthor { return currentProfile }
        return UserProfile(id: UUID(), displayName: resolvedAuthor, username: resolvedAuthor)
    }
    private func retainFocus(_ field: RecipeEditorField) { DispatchQueue.main.async { focusedField = field } }
    private func fieldLabel(_ title: String) -> some View { Text(title).font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.label) }
    private enum RecipeEditorField { case title, summary }
}

struct IngredientInputRow: View {
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
        .frame(height: 48)
    }
}

struct NutritionFactsEditorCard: View {
    @Binding var nutrition: [NutritionFact]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("Nutrition Facts")
                    .font(.custom("Plus Jakarta Sans", size: 22).weight(.semibold))

                if nutrition.isEmpty {
                    Text("Optional — add calories, macros, or any nutrient per serving.")
                        .font(.custom("Inter", size: 12))
                        .foregroundStyle(AppTheme.label)
                } else {
                    HStack(spacing: 8) {
                        Text("Nutrient").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Amount").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Unit").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 32)
                    }
                    .font(.custom("Inter", size: 12))
                    .foregroundStyle(AppTheme.label)

                    ForEach($nutrition) { $fact in
                        NutritionInputRow(fact: $fact) {
                            nutrition.removeAll { $0.id == fact.id }
                        }
                    }
                }

                Button(nutrition.isEmpty ? "Add nutrition" : "Add nutrient", systemImage: "plus") {
                    nutrition.append(NutritionFact(name: nutrition.isEmpty ? "Calories" : "", amount: 0, unit: nutrition.isEmpty ? "kcal" : "g"))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
                .accessibilityHint("Adds a nutrition fact with nutrient, amount, and unit fields")
            }
        }
    }
}

struct NutritionInputRow: View {
    @Binding var fact: NutritionFact
    let remove: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let fieldWidth = (geometry.size.width - 24 - 32) / 3
            HStack(spacing: 8) {
                TextField("Nutrient", text: $fact.name)
                    .figmaInput()
                    .frame(width: fieldWidth)
                TextField("Amount", value: $fact.amount, format: .number)
                    .keyboardType(.decimalPad)
                    .figmaInput()
                    .frame(width: fieldWidth)
                TextField("Unit", text: $fact.unit)
                    .figmaInput()
                    .frame(width: fieldWidth)
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(AppTheme.label)
                        .frame(width: 32, height: 48)
                }
                .accessibilityLabel("Remove \(fact.name.isEmpty ? "nutrition fact" : fact.name)")
            }
        }
        .frame(height: 48)
    }
}

struct MealPlanListView: View {
    @EnvironmentObject private var store: MealStore
    @State private var showCreate = false; @State private var query = ""; @State private var selectedTags: Set<String> = []
    private var tags: [String] { RecipeTagPolicy.mealPlanCatalog(from: store.plans) }
    private var filteredPlans: [MealPlan] { store.plans.filter { plan in (query.isEmpty || plan.name.localizedCaseInsensitiveContains(query) || plan.tags.contains { $0.localizedCaseInsensitiveContains(query) }) && RecipeTagPolicy.matchesAll(plan.tags, selectedTags: selectedTags) } }
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    RecipeTagFilter(selections: $selectedTags, options: tags)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.xxs)

                    ScrollView {
                        if filteredPlans.isEmpty {
                            ContentUnavailableView {
                                NavigationEmptyStateLabel(title: query.isEmpty ? "No meal plans yet" : "No matching meal plans", imageName: "FigmaNavFolder")
                            } description: {
                                Text(query.isEmpty ? "Create a plan to make weeknight cooking easier." : "Try a different search or tag.")
                            } actions: {
                                if query.isEmpty && selectedTags.isEmpty {
                                    Button("Create Plan") { showCreate = true }
                                        .buttonStyle(.borderedProminent)
                                        .tint(AppTheme.primary)
                                        .foregroundStyle(.black)
                                }
                            }
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(filteredPlans) { plan in
                                    NavigationLink { MealPlanDetailView(plan: plan) } label: { PlanCard(plan: plan) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(AppTheme.Spacing.md)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Meal Plans")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search meal plans")
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create meal plan")
                }
            }
            .sheet(isPresented: $showCreate) { MealPlanEditor(plan: nil) }
        }
    }
}

struct PlanCard: View {
    let plan: MealPlan

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    Group { if let data = plan.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() } else { ZStack { LinearGradient(colors: [AppTheme.elevatedSurface, AppTheme.input], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(AppTheme.accent) } } }
                        .frame(width: proxy.size.width, height: proxy.size.width * 0.75)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                Text(plan.name).font(.headline).foregroundStyle(AppTheme.text).lineLimit(1)
                Text("\(plan.weekCount) weeks · \(plan.meals.count) meals").font(.caption).foregroundStyle(AppTheme.label)
                if !plan.tags.isEmpty { TagPreview(tags: plan.tags) }
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.libraryCardContentHeight, maxHeight: AppTheme.Layout.libraryCardContentHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.libraryCardHeight, maxHeight: AppTheme.Layout.libraryCardHeight, alignment: .top)
    }
}

struct PlanRecipeSlot: Identifiable {
    let week: Int; let weekday: Int; let mealType: MealType
    var id: String { "\(week)-\(weekday)-\(mealType.rawValue)" }
}

/// A saved plan is intentionally read-only until the owner explicitly chooses Edit.
/// This mirrors recipes and keeps accidental schedule changes out of browsing.
struct MealPlanDetailView: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var householdStore: HouseholdStore
    let plan: MealPlan
    @State private var showEdit = false
    @State private var confirmHouseholdShare = false
    @State private var shareMessage: String?
    @State private var expandedWeeks: Set<Int> = [1]

    private var displayedPlan: MealPlan { store.plans.first { $0.id == plan.id } ?? plan }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    planImage
                    VStack(alignment: .leading, spacing: 14) {
                        Text(displayedPlan.name)
                            .font(AppTheme.display(.title))
                            .foregroundStyle(AppTheme.text)
                        Text("\(displayedPlan.weekCount) week\(displayedPlan.weekCount == 1 ? "" : "s") · \(displayedPlan.meals.count) meal\(displayedPlan.meals.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.label)
                        if !displayedPlan.tags.isEmpty {
                            TagFlowLayout { ForEach(displayedPlan.tags, id: \.self) { Tag(title: $0) } }
                        }
                        Text("Plan schedule")
                            .font(.custom("Plus Jakarta Sans", size: 21).weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        ForEach(1...displayedPlan.weekCount, id: \.self) { week in weekCard(week) }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .background(AppTheme.background)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                    .offset(y: -15)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(displayedPlan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share with Household", systemImage: "house.fill") { sharePlan() }
                    Button("Edit Meal Plan", systemImage: "pencil") { showEdit = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Meal plan options")
            }
        }
        .sheet(isPresented: $showEdit) {
            if let currentPlan = store.plans.first(where: { $0.id == plan.id }) {
                MealPlanEditor(plan: currentPlan)
            }
        }
        .confirmationDialog("Share this plan with your household?", isPresented: $confirmHouseholdShare) {
            Button("Share plan and \(Set(displayedPlan.meals.map(\.recipeID)).count) recipe\(Set(displayedPlan.meals.map(\.recipeID)).count == 1 ? "" : "s")") { shareDisplayedPlan() }
        } message: {
            Text("This creates collaborative household copies. Your personal plan and recipes stay private and unchanged.")
        }
        .alert("Household", isPresented: Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareMessage ?? "")
        }
    }

    private var planImage: some View {
        Group {
            if let data = displayedPlan.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.42))
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.coverImage, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.xs)
    }

    private func weekCard(_ week: Int) -> some View {
        let meals = displayedPlan.meals.filter { $0.week == week }
        let isExpanded = expandedWeeks.contains(week)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded { expandedWeeks.remove(week) } else { expandedWeeks.insert(week) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Week \(week)").font(.custom("Plus Jakarta Sans", size: 18).weight(.bold))
                            Text("\(meals.count) meal\(meals.count == 1 ? "" : "s")").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundStyle(AppTheme.label)
                    }
                    .foregroundStyle(AppTheme.text)
                }
                .buttonStyle(.plain)
                if isExpanded {
                    ForEach(1...7, id: \.self) { weekday in
                        let dayMeals = meals.filter { $0.weekday == weekday }
                        if !dayMeals.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(weekdayName(weekday)).font(.custom("Inter", size: 12).weight(.bold)).foregroundStyle(AppTheme.label)
                                ForEach(dayMeals) { meal in
                                    HStack(spacing: 8) {
                                        Text(meal.mealType.displayName).font(.custom("Inter", size: 12).weight(.semibold)).frame(width: 72, alignment: .leading)
                                        Text(store.recipe(meal.recipeID)?.title ?? "Missing recipe").font(.custom("Inter", size: 13)).lineLimit(1)
                                    }
                                    .foregroundStyle(AppTheme.text)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func sharePlan() {
        guard householdStore.household != nil else {
            shareMessage = "Create or join a household before sharing meal plans."
            return
        }
        confirmHouseholdShare = true
    }

    private func shareDisplayedPlan() {
        Task {
            do {
                try await householdStore.share(plan: displayedPlan)
                shareMessage = "Meal plan shared with \(householdStore.household?.name ?? "your household")."
            } catch {
                shareMessage = error.localizedDescription
            }
        }
    }
}

struct MealPlanEditor: View {
    @EnvironmentObject private var store: MealStore; @Environment(\.dismiss) private var dismiss
    let existing: MealPlan?
    @State private var name = ""; @State private var tags: [String] = []; @State private var weekCount = 1; @State private var meals: [PlanMeal] = []; @State private var expandedWeek = 1
    @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?; @State private var recipeSlot: PlanRecipeSlot?
    @FocusState private var focusedField: MealPlanEditorField?
    init(plan: MealPlan?) { existing = plan; _name = State(initialValue: plan?.name ?? ""); _tags = State(initialValue: RecipeTagPolicy.normalized(plan?.tags ?? [])); _weekCount = State(initialValue: plan?.weekCount ?? 1); _meals = State(initialValue: plan?.meals ?? []); _imageData = State(initialValue: plan?.imageData) }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        planHero
                        VStack(alignment: .leading, spacing: 14) {
                            editorHeader
                            planDetails
                            Text("Plan schedule").font(.custom("Plus Jakarta Sans", size: 21).weight(.bold)).foregroundStyle(AppTheme.text)
                            ForEach(1...weekCount, id: \.self) { week in weekBlock(week) }
                            Button { weekCount += 1; expandedWeek = weekCount } label: { Label("Add Week", systemImage: "plus").font(.custom("Inter", size: 14).weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12).background(AppTheme.input).foregroundStyle(AppTheme.primary).clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)) }.buttonStyle(.plain)
                        }
                        .padding(AppTheme.Spacing.md)
                        .padding(.bottom, 90)
                        .background(AppTheme.background)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: AppTheme.Radius.control, topTrailingRadius: AppTheme.Radius.control))
                        .offset(y: -15)
                    }
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
                }.clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.coverImage, style: .continuous))
            }.buttonStyle(.plain)
            CircularBackButton(action: { dismiss() }).padding(14)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.xs)
    }

    private var editorHeader: some View {
        Text(existing == nil ? "Create Meal Plan" : "Edit Meal Plan").font(.custom("Plus Jakarta Sans", size: 24).weight(.bold)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planDetails: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plan details").font(.custom("Plus Jakarta Sans", size: 19).weight(.bold)).foregroundStyle(AppTheme.text)
                fieldLabel("Plan name")
                TextField("e.g. Weekday Favorites", text: $name).figmaInput().focused($focusedField, equals: .name).onChange(of: name) { retainFocus(.name) }
                RecipeTagEditor(
                    tags: $tags,
                    suggestions: RecipeTagPolicy.mealPlanCatalog(from: store.plans),
                    helperText: "Add tags to organize and find this meal plan later.",
                    titleFont: .custom("Plus Jakarta Sans", size: 19).weight(.bold),
                    usesSurfaceCard: false
                )
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
    private func retainFocus(_ field: MealPlanEditorField) { DispatchQueue.main.async { focusedField = field } }
    private enum MealPlanEditorField { case name }
    private func setRecipe(_ recipeID: UUID, for slot: PlanRecipeSlot) { meals.removeAll { $0.week == slot.week && $0.weekday == slot.weekday && $0.mealType == slot.mealType }; meals.append(PlanMeal(week: slot.week, weekday: slot.weekday, mealType: slot.mealType, recipeID: recipeID)) }
    private func savePlan() { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.save(plan: MealPlan(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), tags: RecipeTagPolicy.normalized(tags), weekCount: weekCount, meals: meals.filter { $0.week <= weekCount }, imageData: imageData)); dismiss() }
}

private struct PlanRecipePickerSheet: View {
    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    let slot: PlanRecipeSlot
    let select: (UUID) -> Void
    @State private var query = ""
    @State private var selectedTags: Set<String> = []
    private var tags: [String] { RecipeTagPolicy.catalog(from: store.recipes) }
    private var recipes: [Recipe] { store.recipes.filter { RecipeTagPolicy.matches($0, query: query, selectedTags: selectedTags) } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack { Spacer().frame(width: 30); Spacer(); Text("Choose Recipe").font(.custom("Plus Jakarta Sans", size: 26).weight(.bold)).foregroundStyle(AppTheme.text); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) } }
                    Text("\(weekdayName(slot.weekday)) · \(slot.mealType.displayName)").font(.custom("Inter", size: 13)).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search recipes", text: $query).foregroundStyle(AppTheme.text) }.padding(.horizontal, 12).frame(height: 36).background(AppTheme.input).clipShape(Capsule())
                    RecipeTagFilter(selections: $selectedTags, options: tags).frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView { LazyVStack(spacing: 9) { ForEach(recipes) { recipe in Button { select(recipe.id); dismiss() } label: { RecipeSelectionCard(recipe: recipe) }.buttonStyle(.plain) } }.padding(.bottom, 12) }.scrollIndicators(.hidden)
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

struct CalendarView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var scope: CalendarScope = .personal

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if householdStore.household != nil {
                    Picker("Calendar", selection: $scope) {
                        ForEach(CalendarScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(AppTheme.background)
                }
                MealCalendarContent(
                    scope: scope == .household && householdStore.household != nil ? .household : .personal,
                    hidesNavigationBar: false
                )
            }
            .background(AppTheme.background)
        }
        .onChange(of: householdStore.household?.id) { _, householdID in if householdID == nil { scope = .personal } }
    }
}

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month"
    var id: Self { self }
}

private struct CalendarDisplayMeal: Identifiable {
    let id: UUID
    let date: Date
    let mealType: MealType
    let recipeID: UUID
    let householdMeal: HouseholdCalendarMeal?
}

struct MealCalendarContent: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var householdStore: HouseholdStore
    let scope: CalendarScope
    let hidesNavigationBar: Bool
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
        ZStack(alignment: .bottomTrailing) {
                AppTheme.background.ignoresSafeArea()
                Group {
                    if displayMode == .week {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 16) {
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
                                modePicker
                                monthView
                                selectedDayMeals
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 92)
                        }
                    }
                }
            }
            .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
            .navigationTitle(scope == .household ? "Household Calendar" : "Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Meal", systemImage: "plus") { mealTypeToAdd = nil; mealSheetDetent = .large; showMeal = true }
                        Button("Apply Meal Plan", systemImage: "square.stack.3d.up") { planSheetDetent = .large; showPlan = true }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Calendar actions")
                }
            }
            .onAppear { weekBarAnchor = selectedDate; loadWeekFeed(from: selectedDate) }
            .sheet(isPresented: $showMeal) {
                Group {
                    if scope == .household {
                        HouseholdScheduleMealSheet(date: selectedDate, initialType: mealTypeToAdd)
                    } else {
                        ScheduleMealSheet(date: selectedDate, initialType: mealTypeToAdd)
                    }
                }
                .presentationDetents([.medium, .large], selection: $mealSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showPlan) {
                Group {
                    if scope == .household {
                        HouseholdApplyPlanSheet(startDate: selectedDate)
                    } else {
                        ApplyPlanSheet(startDate: selectedDate)
                    }
                }
                .presentationDetents([.medium, .large], selection: $planSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe, allowsHouseholdSharing: scope != .household)
            }
    }

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
                    advanceWeekBarIfNeeded(for: day)
                }
            }
        }
    }

    private var monthView: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarTitle
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(orderedWeekdaySymbols, id: \.self) {
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

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...]) + Array(symbols[..<start])
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(mealAccessibilitySummary(for: day))
        .accessibilityHint("Double-tap to view and edit meals for this day")
    }

    private func monthStatusCluster(for day: Date) -> some View {
        let types = MealType.allCases
        return VStack(spacing: 2) {
            HStack(spacing: 2) { ForEach(Array(types.prefix(2))) { mealStatusBubble(for: day, type: $0) } }
            HStack(spacing: 2) { ForEach(Array(types.dropFirst(2).prefix(2))) { mealStatusBubble(for: day, type: $0) } }
            mealStatusBubble(for: day, type: types[4])
        }
        .accessibilityHidden(true)
    }

    private func mealStatusBubble(for day: Date, type: MealType) -> some View {
        let isScheduled = meals(on: day).contains { $0.mealType == type }
        return Circle()
            .fill(isScheduled ? AppTheme.accent : Color.clear)
            .overlay(Circle().stroke(isScheduled ? AppTheme.accent : AppTheme.mealIndicator, lineWidth: isScheduled ? 1.5 : 1))
            .frame(width: 7, height: 7)
    }

    private func mealAccessibilitySummary(for day: Date) -> String {
        let planned = meals(on: day).map(\.mealType.displayName)
        guard !planned.isEmpty else { return "No meals planned" }
        return "\(planned.count) of \(MealType.allCases.count) meals planned: \(planned.joined(separator: ", "))"
    }

    private var selectedDayMeals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(date: .complete, time: .omitted)).font(.custom("Plus Jakarta Sans", size: 20).weight(.semibold)).foregroundStyle(AppTheme.text)
            if meals(on: selectedDate).isEmpty {
                Text("No meals planned").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.label).padding(.vertical, 16).frame(maxWidth: .infinity).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(meals(on: selectedDate)) { scheduled in
                    if let recipe = recipe(scheduled.recipeID) {
                        scheduledMealCard(scheduled, recipe: recipe)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weeklyMealSlot(_ type: MealType, for date: Date) -> some View {
        let scheduled = meals(on: date).first { $0.mealType == type }
        if let scheduled, let recipe = recipe(scheduled.recipeID) {
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

    private func scheduledMealCard(_ scheduled: CalendarDisplayMeal, recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            Image(scheduled.mealType == .dinner ? "FigmaRecipe1" : "FigmaRecipe3")
                .resizable().scaledToFill().frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(scheduled.mealType.displayName.uppercased()).font(.custom("Inter", size: 10).weight(.bold)).foregroundStyle(AppTheme.label)
                Text(recipe.title).font(.custom("Plus Jakarta Sans", size: 15).weight(.semibold)).foregroundStyle(AppTheme.text)
            }
            Spacer()
            Button(role: .destructive) { remove(scheduled) } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(AppTheme.label).frame(width: 32, height: 32).background(AppTheme.input).clipShape(Circle()) }
        }
        .padding(12).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { selectedRecipe = recipe }
    }

    private func meals(on date: Date) -> [CalendarDisplayMeal] {
        if scope == .household {
            return householdStore.meals(on: date).map {
                CalendarDisplayMeal(id: $0.id, date: $0.date, mealType: $0.mealType, recipeID: $0.recipeID, householdMeal: $0)
            }
        }
        return store.meals(on: date).map {
            CalendarDisplayMeal(id: $0.id, date: $0.date, mealType: $0.mealType, recipeID: $0.recipeID, householdMeal: nil)
        }
    }

    private func recipe(_ id: UUID) -> Recipe? {
        scope == .household ? householdStore.recipe(id) : store.recipe(id)
    }

    private func remove(_ meal: CalendarDisplayMeal) {
        if let householdMeal = meal.householdMeal {
            Task { try? await householdStore.removeCalendarMeal(householdMeal) }
        } else {
            store.calendarMeals.removeAll { $0.id == meal.id }
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
    @State private var selectedTags: Set<String> = []
    @State private var pendingRecipe: Recipe?

    init(date: Date, initialType: MealType? = nil) { self.date = date; _type = State(initialValue: initialType) }

    private var tags: [String] { RecipeTagPolicy.catalog(from: store.recipes) }
    private var filteredRecipes: [Recipe] {
        store.recipes.filter { recipe in
            RecipeTagPolicy.matches(recipe, query: query, selectedTags: selectedTags)
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
                        HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query).foregroundStyle(AppTheme.text) }
                            .padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule())
                        RecipeTagFilter(selections: $selectedTags, options: tags).frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var selectedTags: Set<String> = []
    @State private var showStartCalendar = false
    @State private var showEndCalendar = false

    init(startDate: Date) { self.startDate = startDate; _start = State(initialValue: startDate); _end = State(initialValue: Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate) }
    private var tags: [String] { RecipeTagPolicy.mealPlanCatalog(from: store.plans) }
    private var filteredPlans: [MealPlan] { store.plans.filter { (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }) && RecipeTagPolicy.matchesAll($0.tags, selectedTags: selectedTags) } }
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
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label); TextField("Search", text: $query).foregroundStyle(AppTheme.text) }.padding(.horizontal, 12).frame(height: 34).background(AppTheme.input).clipShape(Capsule())
            RecipeTagFilter(selections: $selectedTags, options: tags).frame(maxWidth: .infinity, alignment: .leading)
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
