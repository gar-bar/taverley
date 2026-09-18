import SwiftUI
import PhotosUI
import UIKit

struct HouseholdProfileCard: View {
    @EnvironmentObject private var householdStore: HouseholdStore

    var body: some View {
        NavigationLink {
            if householdStore.household == nil { HouseholdWelcomeView() } else { HouseholdHomeView() }
        } label: {
            SurfaceCard {
                HStack(spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(householdStore.household?.name ?? "Create or join a household")
                            .font(.custom("Plus Jakarta Sans", size: 18).weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text(householdStore.household.map { _ in "\(householdStore.members.count) member\(householdStore.members.count == 1 ? "" : "s") · Shared recipes and meals" } ?? "Plan and cook together")
                            .font(.custom("Inter", size: 12))
                            .foregroundStyle(AppTheme.label)
                    }
                    Spacer()
                    if householdStore.pendingInvitationCount > 0 {
                        Text("\(householdStore.pendingInvitationCount)")
                            .font(.caption.bold()).foregroundStyle(.black)
                            .frame(width: 24, height: 24).background(AppTheme.primary).clipShape(Circle())
                    }
                    Image(systemName: "chevron.right").foregroundStyle(AppTheme.label)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(householdStore.household == nil ? "Create or join a household" : "Open \(householdStore.household?.name ?? "household")")
    }
}

struct HouseholdNotificationButton: View {
    @EnvironmentObject private var householdStore: HouseholdStore

    var body: some View {
        NavigationLink { HouseholdInvitationInboxView() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: householdStore.pendingInvitationCount > 0 ? "bell.fill" : "bell")
                    .frame(width: 44, height: 44)
                if householdStore.pendingInvitationCount > 0 {
                    Text("\(min(householdStore.pendingInvitationCount, 9))")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 16, height: 16).background(AppTheme.primary).clipShape(Circle())
                        .offset(x: -2, y: 2)
                }
            }
        }
        .accessibilityLabel("Invitations, \(householdStore.pendingInvitationCount) pending")
    }
}

struct HouseholdInvitationInboxView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var workingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if householdStore.receivedInvitations.isEmpty {
                ContentUnavailableView("No invitations", systemImage: "bell", description: Text("Household invitations will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(householdStore.receivedInvitations) { invitation in
                            invitationCard(invitation)
                        }
                    }.padding(16)
                }.refreshable { await householdStore.refreshInvitations() }
            }
        }
        .navigationTitle("Invitations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await householdStore.refreshInvitations() }
        .alert("Couldn’t update invitation", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func invitationCard(_ invitation: HouseholdInvitation) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    InitialsAvatar(profile: invitation.inviter, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invitation.householdName).font(.headline).foregroundStyle(AppTheme.text)
                        Text("Invited by @\(invitation.inviter.username)").font(.caption).foregroundStyle(AppTheme.label)
                    }
                    Spacer()
                }
                Text(invitation.isExpired ? "This invitation has expired." : "Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(invitation.isExpired ? .orange : AppTheme.label)
                if invitation.canRespond {
                    HStack(spacing: 10) {
                        Button("Decline") { respond(invitation, accept: false) }
                            .buttonStyle(.bordered).tint(AppTheme.label).frame(maxWidth: .infinity)
                        Button("Accept") { respond(invitation, accept: true) }
                            .buttonStyle(.borderedProminent).tint(AppTheme.primary).foregroundStyle(.black).frame(maxWidth: .infinity)
                    }.disabled(workingID != nil)
                }
            }
        }
    }

    private func respond(_ invitation: HouseholdInvitation, accept: Bool) {
        workingID = invitation.id
        Task {
            do { try await householdStore.respond(to: invitation, accept: accept) }
            catch { errorMessage = error.localizedDescription }
            workingID = nil
        }
    }
}

struct HouseholdWelcomeView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "house.fill").font(.system(size: 46)).foregroundStyle(AppTheme.primary)
                        .frame(width: 92, height: 92).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text("Cook together").font(.custom("Plus Jakarta Sans", size: 28).weight(.bold)).foregroundStyle(AppTheme.text)
                    Text("Create a household to share recipes, meal plans, and one collaborative meal calendar.")
                        .font(.body).foregroundStyle(AppTheme.label).multilineTextAlignment(.center)
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Household name").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.label)
                            TextField("e.g. The Kazan Kitchen", text: $name).figmaInput()
                            PrimaryButton(title: isCreating ? "Creating…" : "Create Household", icon: "plus") { create() }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        }
                    }
                    if householdStore.pendingInvitationCount > 0 {
                        NavigationLink { HouseholdInvitationInboxView() } label: {
                            Label("View \(householdStore.pendingInvitationCount) pending invitation\(householdStore.pendingInvitationCount == 1 ? "" : "s")", systemImage: "bell.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primary)
                        }
                    }
                }.padding(24)
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t create household", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func create() {
        isCreating = true
        Task {
            do { try await householdStore.createHousehold(name: name) }
            catch { errorMessage = error.localizedDescription }
            isCreating = false
        }
    }
}

struct HouseholdHomeView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var showSettings = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    householdHeader
                    NavigationLink { HouseholdCalendarView() } label: { dashboardRow(title: "Shared Calendar", detail: nextMealText, icon: "calendar") }.buttonStyle(.plain)
                    sectionTitle("Shared Recipes", count: householdStore.recipes.count, destination: AnyView(HouseholdRecipesView()))
                    if householdStore.recipes.isEmpty { emptyRow("Share a recipe to start cooking together.") }
                    else { horizontalRecipes }
                    sectionTitle("Shared Meal Plans", count: householdStore.plans.count, destination: AnyView(HouseholdPlansView()))
                    if householdStore.plans.isEmpty { emptyRow("Shared meal plans will appear here.") }
                    else { horizontalPlans }
                    NavigationLink { HouseholdMembersView() } label: { dashboardRow(title: "Members", detail: "\(householdStore.members.count) people", icon: "person.2.fill") }.buttonStyle(.plain)
                }.padding(16).padding(.bottom, 30)
            }.refreshable { await householdStore.refresh() }
        }
        .navigationTitle(householdStore.household?.name ?? "Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "ellipsis") }.frame(width: 44, height: 44) } }
        .sheet(isPresented: $showSettings) { HouseholdSettingsView() }
    }

    private var householdHeader: some View {
        SurfaceCard {
            HStack(spacing: -8) {
                ForEach(householdStore.members.prefix(5)) { InitialsAvatar(profile: $0.profile, size: 42).overlay(Circle().stroke(AppTheme.surface, lineWidth: 2)) }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(householdStore.isOwner ? "Owner" : "Member").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.primary)
                    Text("Cooking together").font(.caption).foregroundStyle(AppTheme.label)
                }
            }
        }
    }

    private var nextMealText: String {
        guard let meal = householdStore.calendarMeals.filter({ $0.date >= Calendar.current.startOfDay(for: Date()) }).sorted(by: { $0.date < $1.date }).first,
              let recipe = householdStore.recipe(meal.recipeID) else { return "No upcoming meals" }
        return "Next: \(recipe.title) · \(meal.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func dashboardRow(title: String, detail: String, icon: String) -> some View {
        SurfaceCard { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(AppTheme.primary).frame(width: 42, height: 42).background(AppTheme.input).clipShape(RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline).foregroundStyle(AppTheme.text); Text(detail).font(.caption).foregroundStyle(AppTheme.label) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(AppTheme.label) } }
    }

    private func sectionTitle(_ title: String, count: Int, destination: AnyView) -> some View {
        NavigationLink { destination } label: { HStack { Text(title).font(.custom("Plus Jakarta Sans", size: 22).weight(.bold)); Text("\(count)").foregroundStyle(AppTheme.label); Spacer(); Image(systemName: "chevron.right").foregroundStyle(AppTheme.label) }.foregroundStyle(AppTheme.text) }.buttonStyle(.plain)
    }

    private var horizontalRecipes: some View {
        ScrollView(.horizontal) { HStack(spacing: 12) { ForEach(householdStore.recipes.prefix(5)) { item in NavigationLink { HouseholdRecipeDetailView(item: item) } label: { RecipeCard(recipe: item.recipe).frame(width: 176) } } }.padding(.vertical, 2) }.scrollIndicators(.hidden)
    }
    private var horizontalPlans: some View {
        ScrollView(.horizontal) { HStack(spacing: 12) { ForEach(householdStore.plans.prefix(5)) { item in NavigationLink { HouseholdPlanEditor(item: item) } label: { PlanCard(plan: item.plan).frame(width: 176) } } }.padding(.vertical, 2) }.scrollIndicators(.hidden)
    }
    private func emptyRow(_ text: String) -> some View { Text(text).font(.subheadline).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14)) }
}

struct HouseholdRecipesView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var query = ""
    @State private var showCreate = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppTheme.background.ignoresSafeArea()
            ScrollView { VStack(spacing: 12) { HStack { Image(systemName: "magnifyingglass"); TextField("Search shared recipes", text: $query) }.figmaInput(); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(householdStore.recipes.filter { query.isEmpty || $0.recipe.title.localizedCaseInsensitiveContains(query) }) { item in NavigationLink { HouseholdRecipeDetailView(item: item) } label: { RecipeCard(recipe: item.recipe) } } } }.padding(16).padding(.bottom, 110) }
            Button { showCreate = true } label: { Label("New Recipe", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()) }
                .padding(.trailing, 20)
                .padding(.bottom, 90)
        }.navigationTitle("Shared Recipes").sheet(isPresented: $showCreate) { HouseholdRecipeEditor(item: nil) }
    }
}

struct HouseholdRecipeDetailView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdRecipe
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    var body: some View {
        RecipeDetailView(recipe: householdStore.recipes.first(where: { $0.id == item.id })?.recipe ?? item.recipe, allowsHouseholdSharing: false)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Edit", systemImage: "pencil") { showEdit = true }; Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true } } label: { Image(systemName: "ellipsis.circle") } } }
            .sheet(isPresented: $showEdit) { HouseholdRecipeEditor(item: householdStore.recipes.first { $0.id == item.id } ?? item) }
            .confirmationDialog("Delete this shared recipe?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { Task { do { try await householdStore.delete(recipe: item); dismiss() } catch { errorMessage = error.localizedDescription } } } }
            .alert("Couldn’t delete recipe", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}

struct HouseholdRecipeEditor: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdRecipe?
    @State private var title: String
    @State private var summary: String
    @State private var author: String
    @State private var servings: Int
    @State private var tags: String
    @State private var ingredients: [Ingredient]
    @State private var steps: [RecipeStep]
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: HouseholdRecipe?) {
        self.item = item
        let recipe = item?.recipe
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _author = State(initialValue: recipe?.author ?? "Me")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _tags = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
        _ingredients = State(initialValue: recipe?.ingredients ?? [Ingredient(name: "", quantity: 1, unit: "cups")])
        _steps = State(initialValue: recipe?.steps ?? [RecipeStep(text: "")])
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            imageData = try? await photoItem.loadTransferable(type: Data.self)
        }
        .alert("Couldn’t save recipe", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var recipeCoverPicker: some View {
        ZStack(alignment: .topLeading) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.35))
                        }
                    }
                    .frame(height: 180).frame(maxWidth: .infinity).clipped()
                    Label(imageData == nil ? "Add cover image" : "Change image", systemImage: "photo")
                        .font(.custom("Inter", size: 12).weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(AppTheme.input.opacity(0.96)).foregroundStyle(AppTheme.text)
                        .clipShape(Capsule()).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text)
                    .frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle())
            }
            .padding(14)
        }
    }

    private var recipeForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle().fill(AppTheme.primary.opacity(0.35)).frame(width: 25, height: 25)
                VStack(alignment: .leading, spacing: 0) {
                    Text(author.isEmpty ? "Author" : author).font(.custom("Inter", size: 12))
                    Text("@author").font(.custom("Inter", size: 10)).foregroundStyle(AppTheme.label)
                }
            }
            TextField("Add Title", text: $title).figmaInput().padding(.bottom, 8)
            TextField("Add Description", text: $summary, axis: .vertical).lineLimit(3...5).figmaInput().padding(.bottom, 8)
            HStack {
                Text("Serves \(servings)").foregroundStyle(AppTheme.label)
                Stepper("", value: $servings, in: 1...30).labelsHidden()
                TextField("Tags", text: $tags).figmaInput()
            }
            .padding(.bottom, 8)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Ingredients").font(.custom("Plus Jakarta Sans", size: 22).weight(.semibold))
                    HStack(spacing: 8) {
                        Text("Ingredient").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Quantity").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Measure").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                    ForEach($ingredients) { $ingredient in IngredientInputRow(ingredient: $ingredient) }
                    Button("Add Ingredient", systemImage: "plus") { ingredients.append(Ingredient(name: "", quantity: 1, unit: "")) }
                        .buttonStyle(.bordered).tint(AppTheme.primary)
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Instructions").font(.custom("Plus Jakarta Sans", size: 22).weight(.semibold))
                    ForEach($steps) { $step in TextField("Add Instructions", text: $step.text, axis: .vertical).lineLimit(2...4).figmaInput() }
                    Button("Add Step", systemImage: "plus") { steps.append(RecipeStep(text: "")) }
                        .buttonStyle(.bordered).tint(AppTheme.primary)
                }
            }
            PrimaryButton(title: isSaving ? "Saving…" : "Save Recipe") { save() }
                .disabled(isSaving || !isValid)
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ingredients.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() {
        let recipe = Recipe(
            id: item?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            author: author.isEmpty ? "Me" : author,
            servings: servings,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            ingredients: ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            steps: steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            nutrition: item?.recipe.nutrition ?? [],
            imageData: imageData,
            notes: item?.recipe.notes ?? "",
            createdAt: item?.recipe.createdAt ?? Date()
        )
        isSaving = true
        Task {
            do { try await householdStore.save(recipe: recipe, existingVersion: item?.version); dismiss() }
            catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}

struct HouseholdPlansView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var showCreate = false
    var body: some View { ZStack(alignment: .bottomTrailing) { AppTheme.background.ignoresSafeArea(); ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(householdStore.plans) { item in NavigationLink { HouseholdPlanEditor(item: item) } label: { PlanCard(plan: item.plan) } } }.padding(16).padding(.bottom, 110) }; Button { showCreate = true } label: { Label("New Plan", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(Capsule()) }.padding(.trailing, 20).padding(.bottom, 90) }.navigationTitle("Shared Meal Plans").sheet(isPresented: $showCreate) { HouseholdPlanEditor(item: nil) } }
}

struct HouseholdPlanEditor: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdMealPlan?
    @State private var name: String
    @State private var tags: String
    @State private var weekCount: Int
    @State private var meals: [PlanMeal]
    @State private var expandedWeek = 1
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var recipeSlot: PlanRecipeSlot?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: HouseholdMealPlan?) {
        self.item = item
        _name = State(initialValue: item?.plan.name ?? "")
        _tags = State(initialValue: item?.plan.tags.joined(separator: ", ") ?? "")
        _weekCount = State(initialValue: item?.plan.weekCount ?? 1)
        _meals = State(initialValue: item?.plan.meals ?? [])
        _imageData = State(initialValue: item?.plan.imageData)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        planHero
                        Text(item == nil ? "Create Meal Plan" : "Edit Meal Plan")
                            .font(.custom("Plus Jakarta Sans", size: 24).weight(.bold)).foregroundStyle(AppTheme.text)
                        planDetails
                        Text("Plan schedule").font(.custom("Plus Jakarta Sans", size: 21).weight(.bold)).foregroundStyle(AppTheme.text)
                        ForEach(1...weekCount, id: \.self) { week in weekBlock(week) }
                        Button { weekCount += 1; expandedWeek = weekCount } label: {
                            Label("Add Week", systemImage: "plus").font(.custom("Inter", size: 14).weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(AppTheme.input).foregroundStyle(AppTheme.primary).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16).padding(.bottom, 90)
                }
                .scrollIndicators(.hidden)
                PrimaryButton(title: isSaving ? "Saving…" : (item == nil ? "Create Meal Plan" : "Save Changes")) { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .padding(.horizontal, 16).padding(.bottom, 16).background(AppTheme.background.opacity(0.96))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $recipeSlot) { slot in
            HouseholdPlanRecipePickerSheet(slot: slot) { recipeID in setRecipe(recipeID, for: slot) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            imageData = try? await photoItem.loadTransferable(type: Data.self)
        }
        .alert("Couldn’t save plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var planHero: some View {
        ZStack(alignment: .topLeading) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image("FigmaHero").resizable().scaledToFill().overlay(AppTheme.background.opacity(0.42)) }
                    }
                    .frame(height: 180).frame(maxWidth: .infinity).clipped()
                    Label(imageData == nil ? "Add cover image" : "Change image", systemImage: "photo")
                        .font(.custom("Inter", size: 12).weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(AppTheme.input.opacity(0.96)).foregroundStyle(AppTheme.text).clipShape(Capsule()).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(AppTheme.text)
                    .frame(width: 28, height: 28).background(AppTheme.background.opacity(0.94)).clipShape(Circle())
            }
            .padding(14)
        }
    }

    private var planDetails: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plan details").font(.custom("Plus Jakarta Sans", size: 19).weight(.bold)).foregroundStyle(AppTheme.text)
                fieldLabel("Plan name")
                TextField("e.g. Weekday Favorites", text: $name).figmaInput()
                fieldLabel("Labels")
                TextField("e.g. Easy, Family", text: $tags).figmaInput()
                Text("Add weeks below to build the plan duration.").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
            }
        }
    }

    private func weekBlock(_ week: Int) -> some View {
        let weekMeals = meals.filter { $0.week == week }
        return VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expandedWeek = expandedWeek == week ? 0 : week } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Week \(week)").font(.custom("Plus Jakarta Sans", size: 18).weight(.bold))
                        Text("\(weekMeals.count) meal\(weekMeals.count == 1 ? "" : "s")").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                    }
                    Spacer()
                    Image(systemName: expandedWeek == week ? "chevron.up" : "chevron.down").foregroundStyle(AppTheme.label)
                }
                .foregroundStyle(AppTheme.text).padding(14)
            }
            .buttonStyle(.plain)
            if expandedWeek == week {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(1...7, id: \.self) { weekday in daySection(weekday, week: week) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func daySection(_ weekday: Int, week: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(weekdayName(weekday)).font(.custom("Inter", size: 12).weight(.bold)).foregroundStyle(AppTheme.label).padding(.top, 5)
            ForEach(MealType.allCases) { type in mealSlot(weekday: weekday, week: week, type: type) }
        }
    }

    private func mealSlot(weekday: Int, week: Int, type: MealType) -> some View {
        let assigned = meals.first { $0.week == week && $0.weekday == weekday && $0.mealType == type }
        return HStack(spacing: 8) {
            Text(type.displayName).font(.custom("Inter", size: 11).weight(.semibold)).foregroundStyle(AppTheme.text).frame(width: 92, alignment: .leading)
            if let assigned, let recipe = householdStore.recipe(assigned.recipeID) {
                HStack {
                    Text(recipe.title).font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.text).lineLimit(1)
                    Spacer()
                    Button { meals.removeAll { $0.id == assigned.id } } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.label) }
                }
                .padding(.horizontal, 10).frame(height: 29).background(AppTheme.background.opacity(0.55)).clipShape(Capsule())
            } else {
                Button { recipeSlot = PlanRecipeSlot(week: week, weekday: weekday, mealType: type) } label: {
                    HStack {
                        Text("Select recipe").font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.label)
                    }
                    .padding(.horizontal, 10).frame(height: 29).background(AppTheme.input).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.custom("Inter", size: 12).weight(.semibold)).foregroundStyle(AppTheme.label)
    }

    private func setRecipe(_ recipeID: UUID, for slot: PlanRecipeSlot) {
        meals.removeAll { $0.week == slot.week && $0.weekday == slot.weekday && $0.mealType == slot.mealType }
        meals.append(PlanMeal(week: slot.week, weekday: slot.weekday, mealType: slot.mealType, recipeID: recipeID))
    }

    private func save() {
        let plan = MealPlan(
            id: item?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            weekCount: weekCount,
            meals: meals.filter { $0.week <= weekCount },
            imageData: imageData,
            createdAt: item?.plan.createdAt ?? Date()
        )
        isSaving = true
        Task {
            do { try await householdStore.save(plan: plan, existingVersion: item?.version); dismiss() }
            catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}

private struct HouseholdPlanRecipePickerSheet: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let slot: PlanRecipeSlot
    let select: (UUID) -> Void
    @State private var query = ""

    private var recipes: [HouseholdRecipe] {
        householdStore.recipes.filter {
            query.isEmpty || $0.recipe.title.localizedCaseInsensitiveContains(query)
                || $0.recipe.tags.contains { $0.localizedCaseInsensitiveContains(query) }
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
                        Text("Choose Recipe").font(.custom("Plus Jakarta Sans", size: 26).weight(.bold)).foregroundStyle(AppTheme.text)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(AppTheme.text).frame(width: 30, height: 30) }
                    }
                    Text("\(weekdayName(slot.weekday)) · \(slot.mealType.displayName)").font(.custom("Inter", size: 13)).foregroundStyle(AppTheme.label).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.label)
                        TextField("Search recipes", text: $query).foregroundStyle(AppTheme.text)
                    }
                    .padding(.horizontal, 12).frame(height: 36).background(AppTheme.input).clipShape(Capsule())
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(recipes) { item in
                                Button { select(item.id); dismiss() } label: {
                                    HStack(spacing: 10) {
                                        Group {
                                            if let data = item.recipe.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                                            else { Image(item.recipe.title == "Apple Pie" ? "FigmaRecipe2" : "FigmaRecipe3").resizable().scaledToFill() }
                                        }
                                        .frame(width: 56, height: 56).clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.recipe.title).font(.custom("Plus Jakarta Sans", size: 17).weight(.semibold)).foregroundStyle(AppTheme.text)
                                            Text(item.recipe.author).font(.custom("Inter", size: 12)).foregroundStyle(AppTheme.label)
                                            HStack(spacing: 6) { ForEach(item.recipe.tags.prefix(2), id: \.self) { Tag(title: $0) } }
                                        }
                                        Spacer()
                                    }
                                    .padding(9).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }
}

struct HouseholdCalendarView: View {
    var body: some View {
        MealCalendarContent(scope: .household, hidesNavigationBar: false)
            .navigationTitle("Household Calendar")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct HouseholdScheduleMealSheet: View {
    @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss
    let date: Date; @State private var selectedType: MealType; @State private var query = ""
    init(date: Date, initialType: MealType? = nil) {
        self.date = date
        _selectedType = State(initialValue: initialType ?? .dinner)
    }
    var body: some View { NavigationStack { ZStack { AppTheme.background.ignoresSafeArea(); VStack(spacing: 12) { Picker("Meal", selection: $selectedType) { ForEach(MealType.allCases) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented); HStack { Image(systemName: "magnifyingglass"); TextField("Search household recipes", text: $query) }.figmaInput(); ScrollView { LazyVStack(spacing: 9) { ForEach(householdStore.recipes.filter { query.isEmpty || $0.recipe.title.localizedCaseInsensitiveContains(query) }) { item in Button { Task { try? await householdStore.schedule(recipeID: item.id, on: date, type: selectedType); dismiss() } } label: { RecipeSelectionCard(recipe: item.recipe) }.buttonStyle(.plain) } } } }.padding(16) }.navigationTitle("Add Household Meal").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
}

struct HouseholdApplyPlanSheet: View {
    @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss
    let startDate: Date; @State private var replaceExisting = false; @State private var errorMessage: String?
    var body: some View { NavigationStack { ZStack { AppTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing: 12) { Toggle("Replace existing meals", isOn: $replaceExisting).tint(AppTheme.primary).padding(12).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12)); ForEach(householdStore.plans) { item in Button { apply(item.plan) } label: { PlanCard(plan: item.plan) }.buttonStyle(.plain) } }.padding(16) } }.navigationTitle("Apply Household Plan").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }.alert("Couldn’t apply plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") } }
    private func apply(_ plan: MealPlan) { Task { do { try await householdStore.apply(plan: plan, from: startDate, replaceExisting: replaceExisting); dismiss() } catch { errorMessage = error.localizedDescription } } }
}

struct HouseholdMembersView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @State private var showInvite = false; @State private var transferMember: HouseholdMember?; @State private var removeMember: HouseholdMember?; @State private var errorMessage: String?
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            List {
                Section("Members") {
                    ForEach(householdStore.members) { member in
                        HStack {
                            InitialsAvatar(profile: member.profile, size: 42)
                            VStack(alignment: .leading) {
                                Text(member.profile.username)
                                Text("@\(member.profile.username)").font(.caption).foregroundStyle(AppTheme.label)
                            }
                            Spacer()
                            Text(member.role == .owner ? "Owner" : "Member")
                                .font(.caption).foregroundStyle(member.role == .owner ? AppTheme.primary : AppTheme.label)
                            if householdStore.isOwner && member.role == .member {
                                Menu {
                                    Button("Make owner") { transferMember = member }
                                    Button("Remove", role: .destructive) { removeMember = member }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            }
                        }.listRowBackground(AppTheme.surface)
                    }
                }
                if householdStore.isOwner {
                    Section("Pending invitations") {
                        ForEach(householdStore.invitations.filter { $0.householdID == householdStore.household?.id }) { invitation in
                            HStack {
                                Text("@\(invitation.invitee?.username ?? "pending")")
                                Spacer()
                                Button("Revoke", role: .destructive) { Task { try? await householdStore.revoke(invitation) } }
                            }.listRowBackground(AppTheme.surface)
                        }
                    }
                }
            }.scrollContentBackground(.hidden)
        }
        .navigationTitle("Members")
        .toolbar {
            if householdStore.isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInvite = true } label: { Image(systemName: "person.badge.plus") }.frame(width: 44, height: 44)
                }
            }
        }
        .sheet(isPresented: $showInvite) { HouseholdInviteView() }
        .confirmationDialog("Transfer ownership to \(transferMember?.profile.username ?? "this member")?", isPresented: Binding(get: { transferMember != nil }, set: { if !$0 { transferMember = nil } })) {
            Button("Transfer ownership") {
                guard let member = transferMember else { return }
                Task { do { try await householdStore.transferOwnership(to: member) } catch { errorMessage = error.localizedDescription }; transferMember = nil }
            }
        }
        .confirmationDialog("Remove \(removeMember?.profile.username ?? "this member")?", isPresented: Binding(get: { removeMember != nil }, set: { if !$0 { removeMember = nil } })) {
            Button("Remove", role: .destructive) {
                guard let member = removeMember else { return }
                Task { do { try await householdStore.remove(member) } catch { errorMessage = error.localizedDescription }; removeMember = nil }
            }
        }
        .alert("Household update failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

private struct HouseholdInviteView: View {
    @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss
    @State private var query = ""; @State private var results: [UserProfile] = []; @State private var isSearching = false; @State private var errorMessage: String?
    var body: some View { NavigationStack { ZStack { AppTheme.background.ignoresSafeArea(); VStack(spacing: 12) { HStack { Image(systemName: "magnifyingglass"); TextField("Search by username", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled() }.figmaInput().onSubmit { search() }; Button("Search") { search() }.buttonStyle(.borderedProminent).tint(AppTheme.primary).foregroundStyle(.black).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching); ScrollView { LazyVStack(spacing: 9) { ForEach(results) { profile in HStack { InitialsAvatar(profile: profile, size: 44); Text(profile.username).foregroundStyle(AppTheme.text); Spacer(); Button("Invite") { invite(profile) }.buttonStyle(.bordered).tint(AppTheme.primary) }.padding(10).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14)) } } } }.padding(16) }.navigationTitle("Invite someone").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } } }.alert("Invite failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") } }
    private func search() { isSearching = true; Task { do { results = try await householdStore.searchProfiles(query) } catch { errorMessage = error.localizedDescription }; isSearching = false } }
    private func invite(_ profile: UserProfile) { Task { do { try await householdStore.invite(username: profile.username); results.removeAll { $0.id == profile.id } } catch { errorMessage = error.localizedDescription } } }
}

private struct HouseholdSettingsView: View {
    @EnvironmentObject private var householdStore: HouseholdStore; @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var confirmDelete = false; @State private var confirmLeave = false; @State private var errorMessage: String?
    var body: some View { NavigationStack { Form { if householdStore.isOwner { Section("Household name") { TextField("Name", text: $name); Button("Save Name") { run { try await householdStore.rename(name) } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }; Section { Button("Delete Household", role: .destructive) { confirmDelete = true } } } else { Section { Button("Leave Household", role: .destructive) { confirmLeave = true } } } }.scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("Household Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.onAppear { name = householdStore.household?.name ?? "" } }.confirmationDialog("Delete this household and all shared content?", isPresented: $confirmDelete) { Button("Delete Household", role: .destructive) { run { try await householdStore.deleteHousehold(); dismiss() } } }.confirmationDialog("Leave this household?", isPresented: $confirmLeave) { Button("Leave", role: .destructive) { run { try await householdStore.leave(); dismiss() } } }.alert("Household update failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") } }
    private func run(_ operation: @escaping () async throws -> Void) { Task { do { try await operation() } catch { errorMessage = error.localizedDescription } } }
}

struct InitialsAvatar: View {
    let profile: UserProfile; var size: CGFloat
    private var initials: String { profile.username.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    var body: some View { Text(initials).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.black).frame(width: size, height: size).background(AppTheme.primary).clipShape(Circle()).accessibilityLabel(profile.username) }
}
