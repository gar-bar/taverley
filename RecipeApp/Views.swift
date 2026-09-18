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
                    .onAppear { feedStore.deactivateAccount(); householdStore.deactivateAccount() }
            } else if let session = authentication.session, let dataClient = authentication.dataClient {
                RootView()
                    .task(id: session.accessToken) {
                        await store.activateAccount(session, client: dataClient)
                        await feedStore.activateAccount(session, client: dataClient)
                        await householdStore.activateAccount(session, client: dataClient)
                    }
            } else {
                EmailCodeSignInView()
                    .onAppear {
                        store.deactivateAccount()
                        feedStore.deactivateAccount()
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
                        .padding(.top, 8)

                    fieldLabel("Password", top: 18)
                    passwordField("Password", text: $password, contentType: mode == .createAccount ? .newPassword : .password)
                        .padding(.top, 8)

                    if mode == .createAccount {
                        fieldLabel("Confirm password", top: 18)
                        passwordField("Confirm password", text: $passwordConfirmation, contentType: .newPassword)
                            .padding(.top, 8)
                        PasswordRequirementsView(password: password, confirmation: passwordConfirmation)
                            .padding(.top, 12)
                    }

                    Button(action: submit) { buttonLabel(mode.buttonTitle) }
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.top, 14)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.custom("Inter", size: 14))
                            .foregroundStyle(.red)
                            .padding(.top, 16)
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

    private func passwordField(_ title: String, text: Binding<String>, contentType: UITextContentType) -> some View {
        HStack {
            Group {
                if showsPassword { TextField(title, text: text) } else { SecureField(title, text: text) }
            }
            .textContentType(contentType)
            Button { showsPassword.toggle() } label: { Image(systemName: showsPassword ? "eye.slash" : "eye") }
                .accessibilityLabel(showsPassword ? "Hide passwords" : "Show passwords")
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
    @EnvironmentObject private var authentication: AuthenticationStore
    let onBack: () -> Void
    @State private var avatarItem: PhotosPickerItem?
    @AppStorage("profileAvatarImageData") private var avatarImageData: Data?
    @State private var showAccountOptions = false
    @State private var showDeleteAccount = false
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
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(AppTheme.text)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 2) {
                            NavigationLink {
                                MyFavouritesView()
                            } label: {
                                Image(systemName: "star")
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(AppTheme.text)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("My favourites")

                            Button { showAccountOptions = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(AppTheme.text)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
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
                                Text(feedStore.currentProfile?.username ?? "Garnet")
                                    .font(.custom("Plus Jakarta Sans", size: 34).weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                            }

                            HStack(spacing: 34) {
                                ProfileStat(title: "Following", value: "0")
                                ProfileStat(title: "Followers", value: "0")
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)

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
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPostID) { postID in
            PostDetailView(postID: postID)
        }
        }
        .confirmationDialog("Account", isPresented: $showAccountOptions, titleVisibility: .visible) {
            Button("Sign out") { authentication.signOut() }
            Button("Delete account", role: .destructive) { showDeleteAccount = true }
        } message: {
            Text("Manage your Taverley account.")
        }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountView() }
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
        .onChange(of: selectedKind) { _ in
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
                Button("Retry loading more", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
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
                ContentUnavailableView(
                    "No recipes yet",
                    systemImage: "book.closed",
                    description: Text("Your recipes will appear here.")
                )
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
    @EnvironmentObject private var store: MealStore; @EnvironmentObject private var feedStore: FeedStore; @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss; let recipe: Recipe; var allowsHouseholdSharing = true; @State private var scale = 1.0; @State private var ingredientsOpen = true; @State private var stepsOpen = false; @State private var nutritionOpen = false; @State private var shareMessage: String?; @State private var showEdit = false
    var body: some View { ZStack { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing: 0) {
        ZStack(alignment: .top) {
            Group {
                if let data = displayedRecipe.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                else { Image("FigmaHero").resizable().scaledToFill() }
            }.frame(height: 180).clipped().overlay(AppTheme.background.opacity(0.28))
            HStack { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text).frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle()) }; Spacer(); if allowsHouseholdSharing { Button { Task { try? await feedStore.toggleRecipeFavourite(recipeID: displayedRecipe.id) } } label: { Image(systemName: feedStore.favouritedRecipeIDs.contains(displayedRecipe.id) ? "star.fill" : "star").foregroundStyle(feedStore.favouritedRecipeIDs.contains(displayedRecipe.id) ? AppTheme.primary : AppTheme.text) }.accessibilityLabel(feedStore.favouritedRecipeIDs.contains(displayedRecipe.id) ? "Remove recipe from favourites" : "Favourite recipe"); Button { shareRecipe() } label: { Image(systemName: "house.badge.plus") }.accessibilityLabel("Share recipe to household") }; if isPersonalRecipe { Button { showEdit = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit recipe") } }.font(.body.weight(.semibold)).foregroundStyle(AppTheme.text).padding(.horizontal, 16).padding(.top, 14)
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) { Circle().fill(AppTheme.primary.opacity(0.35)).frame(width: 25, height: 25).overlay(Image(systemName: "person.fill").font(.caption)); VStack(alignment: .leading, spacing: 0) { Text(displayedRecipe.author).font(.custom("Inter", size: 12).weight(.medium)); Text("@\(displayedRecipe.author.lowercased())").font(.custom("Inter", size: 10)).foregroundStyle(AppTheme.label) }; Spacer(); VStack(alignment: .trailing, spacing: 2) { Label("4.8 (30)", systemImage: "star.fill").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.primary); Text("30 Minutes").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label) } }
            Text(displayedRecipe.title).font(.custom("Plus Jakarta Sans", size: 28).weight(.bold)).foregroundStyle(AppTheme.text)
            Text(displayedRecipe.summary).font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            Accordion(title: "Ingredients", isOpen: $ingredientsOpen) { Picker("Scale", selection: $scale) { Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }.pickerStyle(.segmented); ForEach(displayedRecipe.ingredients) { item in Text("• \((item.quantity * scale).formatted(.number.precision(.fractionLength(0...2)))) \(item.unit) \(item.name)").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading) } }
            Accordion(title: "Instructions", isOpen: $stepsOpen) { ForEach(Array(displayedRecipe.steps.enumerated()), id: \.element.id) { index, step in Text("\(index + 1). \(step.text)").font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4) } }
            Accordion(title: "Nutrition Facts", isOpen: $nutritionOpen) { ForEach(displayedRecipe.nutrition) { fact in HStack { Text(fact.name); Spacer(); Text("\(fact.amount.formatted()) \(fact.unit)") }.font(.custom("Inter", size: 14)).foregroundStyle(AppTheme.text) } }
        }.padding(16).padding(.bottom, 28).background(AppTheme.background).clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)).offset(y: -15)
    } }.scrollIndicators(.hidden) }.toolbar(.hidden, for: .navigationBar).sheet(isPresented: $showEdit) { if let currentRecipe = store.recipe(recipe.id) { RecipeEditor(recipe: currentRecipe) } }.alert("Household", isPresented: Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(shareMessage ?? "") } }

    private var isPersonalRecipe: Bool { store.recipe(recipe.id) != nil }
    private var displayedRecipe: Recipe { store.recipe(recipe.id) ?? recipe }

    private func shareRecipe() {
        guard householdStore.household != nil else { shareMessage = "Create or join a household before sharing recipes."; return }
        Task { do { try await householdStore.share(recipe: displayedRecipe); shareMessage = "Recipe shared with \(householdStore.household?.name ?? "your household")." } catch { shareMessage = error.localizedDescription } }
    }
}

struct Accordion<Content: View>: View { let title: String; @Binding var isOpen: Bool; @ViewBuilder let content: Content; var body: some View { SurfaceCard { VStack(alignment: .leading, spacing: 12) { Button { withAnimation { isOpen.toggle() } } label: { HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); Image(systemName: isOpen ? "chevron.up" : "chevron.down") }.foregroundStyle(AppTheme.text) }; if isOpen { content } } } } }

struct RecipeEditor: View {
    @EnvironmentObject private var store: MealStore; @Environment(\.dismiss) private var dismiss
    let recipe: Recipe?
    @State private var title: String; @State private var summary: String; @State private var author: String; @State private var servings: Int; @State private var tags: String; @State private var ingredients: [Ingredient]; @State private var steps: [RecipeStep]; @State private var nutrition: [NutritionFact]; @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?

    init(recipe: Recipe? = nil) {
        self.recipe = recipe
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _author = State(initialValue: recipe?.author ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _tags = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
        _ingredients = State(initialValue: recipe?.ingredients ?? [Ingredient(name: "", quantity: 1, unit: "cups")])
        _steps = State(initialValue: recipe?.steps ?? [RecipeStep(text: "")])
        _nutrition = State(initialValue: recipe?.nutrition ?? [])
        _imageData = State(initialValue: recipe?.imageData)
    }
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
            NutritionFactsEditorCard(nutrition: $nutrition)
            PrimaryButton(title: recipe == nil ? "Save Recipe" : "Save Changes") { saveRecipe() }
        }
    }

    private func saveRecipe() {
        let updatedRecipe = Recipe(id: recipe?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, author: author.isEmpty ? "Me" : author, servings: servings, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, ingredients: ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, steps: steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, nutrition: nutrition.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, imageData: imageData, notes: recipe?.notes ?? "", createdAt: recipe?.createdAt ?? Date())
        guard !updatedRecipe.title.isEmpty, !updatedRecipe.ingredients.isEmpty, !updatedRecipe.steps.isEmpty else { return }
        store.save(recipe: updatedRecipe)
        dismiss()
    }
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
        .frame(height: 44)
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
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("Remove \(fact.name.isEmpty ? "nutrition fact" : fact.name)")
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

struct PlanRecipeSlot: Identifiable {
    let week: Int; let weekday: Int; let mealType: MealType
    var id: String { "\(week)-\(weekday)-\(mealType.rawValue)" }
}

struct MealPlanEditor: View {
    @EnvironmentObject private var store: MealStore; @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss
    let existing: MealPlan?
    @State private var name = ""; @State private var tagText = ""; @State private var weekCount = 1; @State private var meals: [PlanMeal] = []; @State private var expandedWeek = 1
    @State private var photoItem: PhotosPickerItem?; @State private var imageData: Data?; @State private var recipeSlot: PlanRecipeSlot?; @State private var confirmHouseholdShare = false; @State private var shareMessage: String?
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
        .confirmationDialog("Share this plan with your household?", isPresented: $confirmHouseholdShare) {
            Button("Share plan and \(Set(meals.map(\.recipeID)).count) recipe\(Set(meals.map(\.recipeID)).count == 1 ? "" : "s")") { sharePlan() }
        } message: { Text("This creates collaborative household copies. Your personal plan and recipes stay private and unchanged.") }
        .alert("Household", isPresented: Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(shareMessage ?? "") }
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
            if existing != nil {
                HStack { Spacer(); Button { if householdStore.household == nil { shareMessage = "Create or join a household before sharing meal plans." } else { confirmHouseholdShare = true } } label: { Image(systemName: "house.badge.plus").foregroundStyle(AppTheme.text).frame(width: 36, height: 36).background(AppTheme.background.opacity(0.94)).clipShape(Circle()) }.accessibilityLabel("Share meal plan to household") }.padding(14)
            }
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
    private func sharePlan() { guard let existing else { return }; Task { do { try await householdStore.share(plan: existing); shareMessage = "Meal plan shared with \(householdStore.household?.name ?? "your household")." } catch { shareMessage = error.localizedDescription } } }
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
                    hidesNavigationBar: true
                )
            }
            .background(AppTheme.background)
        }
        .onChange(of: householdStore.household?.id) { householdID in if householdID == nil { scope = .personal } }
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
            .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
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

    private var header: some View { LibraryHeader(title: scope == .household ? "Household Calendar" : "Meal Planning") }

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
        let isScheduled = meals(on: day).contains { $0.mealType == type }
        return Circle()
            .fill(isScheduled ? AppTheme.mealIndicator : Color.clear)
            .overlay(Circle().stroke(AppTheme.mealIndicator, lineWidth: 1))
            .frame(width: 7, height: 7)
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

    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button { planSheetDetent = .large; showPlan = true } label: { Label("Apply plan", systemImage: "square.stack.3d.up.fill").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 11).background(AppTheme.surface).foregroundStyle(AppTheme.text).clipShape(Capsule()) }
            Button { mealTypeToAdd = nil; mealSheetDetent = .large; showMeal = true } label: { Label("Add Meal", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()) }
        }
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
