import SwiftUI
import UIKit

enum AppTheme {
    // Brand tokens from V1. Names describe intent so views do not depend on raw colours.
    static let canvas = Color(red: 15/255, green: 13/255, blue: 20/255)
    static let surface = Color(red: 27/255, green: 23/255, blue: 36/255)
    static let elevatedSurface = Color(red: 37/255, green: 31/255, blue: 48/255)
    static let input = Color(red: 46/255, green: 39/255, blue: 59/255)
    static let separator = Color(red: 57/255, green: 48/255, blue: 72/255)
    static let accent = Color(red: 196/255, green: 142/255, blue: 255/255)
    static let mealIndicator = Color(red: 92/255, green: 52/255, blue: 127/255)
    static let textPrimary = Color(red: 244/255, green: 238/255, blue: 247/255)
    static let textSecondary = Color(red: 163/255, green: 155/255, blue: 174/255)
    static let success = Color.green
    static let warning = Color.orange
    static let destructive = Color.red

    // Compatibility aliases while individual screens migrate.
    static let background = canvas
    static let border = separator
    static let primary = accent
    static let text = textPrimary
    static let label = textSecondary

    enum Spacing { static let xxs: CGFloat = 4; static let xs: CGFloat = 8; static let sm: CGFloat = 12; static let md: CGFloat = 16; static let lg: CGFloat = 24 }
    enum Radius { static let control: CGFloat = 12; static let card: CGFloat = 16 }

    static func display(_ style: Font.TextStyle = .title2) -> Font { .system(style, design: .rounded).weight(.bold) }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(AppTheme.Spacing.sm).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)) }
}

struct Tag: View {
    let title: String
    var body: some View { Text(title).font(.caption2.weight(.medium)).foregroundStyle(AppTheme.textPrimary).padding(.horizontal, AppTheme.Spacing.xs).padding(.vertical, AppTheme.Spacing.xxs).background(AppTheme.input).clipShape(Capsule()) }
}

struct NavigationEmptyStateLabel: View {
    let title: String
    let imageName: String

    var body: some View {
        VStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            Text(title).font(.title3.weight(.semibold))
        }
    }
}

struct TagPreview: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(2), id: \.self) { Tag(title: $0) }
            if tags.count > 2 { Tag(title: "+\(tags.count - 2)") }
        }
        .lineLimit(1)
    }
}

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0; var y: CGFloat = 0; var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + (x == 0 ? 0 : spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct RemovableTagChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
            .accessibilityLabel("Remove \(title) tag")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(AppTheme.input)
        .clipShape(Capsule())
    }
}

struct RecipeTagEditor: View {
    @Binding var tags: [String]
    let suggestions: [String]
    let helperText: String
    let titleFont: Font
    let usesSurfaceCard: Bool
    @State private var draft = ""

    init(
        tags: Binding<[String]>,
        suggestions: [String],
        helperText: String = "Add tags to organize and find this recipe later.",
        titleFont: Font = .title3.weight(.semibold),
        usesSurfaceCard: Bool = true
    ) {
        _tags = tags
        self.suggestions = suggestions
        self.helperText = helperText
        self.titleFont = titleFont
        self.usesSurfaceCard = usesSurfaceCard
    }

    private var unusedSuggestions: [String] {
        let selectedKeys = Set(tags.map(RecipeTagPolicy.key(for:)))
        return suggestions.filter { !selectedKeys.contains(RecipeTagPolicy.key(for: $0)) }
    }

    var body: some View {
        Group {
            if usesSurfaceCard { SurfaceCard { editorContent } }
            else { editorContent }
        }
        .onAppear { tags = RecipeTagPolicy.normalized(tags) }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags").font(titleFont)
            Text(helperText)
                .font(.footnote).foregroundStyle(AppTheme.label)
            if !tags.isEmpty {
                TagFlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        RemovableTagChip(title: tag) { tags.removeAll { RecipeTagPolicy.key(for: $0) == RecipeTagPolicy.key(for: tag) } }
                    }
                }
            }
            TextField("Add a tag", text: $draft)
                .figmaInput()
                .onSubmit { add(draft) }
                .onChange(of: draft) { _, value in
                    guard value.contains(",") else { return }
                    let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                    parts.dropLast().forEach(add)
                    draft = parts.last ?? ""
                }
            if !unusedSuggestions.isEmpty {
                Text("Suggestions").font(.footnote.weight(.semibold)).foregroundStyle(AppTheme.label)
                TagFlowLayout {
                    ForEach(unusedSuggestions, id: \.self) { tag in
                        Button { add(tag) } label: {
                            Label(tag, systemImage: "plus").font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.primary).padding(.horizontal, 9).padding(.vertical, 6)
                                .background(AppTheme.input).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add(_ rawTag: String) {
        tags = RecipeTagPolicy.normalized(tags + [rawTag])
        draft = ""
    }
}

struct RecipeTagFilter: View {
    let title: String
    @Binding var selections: Set<String>
    let options: [String]
    let buttonHeight: CGFloat
    let showsActiveSelections: Bool
    @State private var isPresented = false
    @State private var query = ""

    init(title: String = "Tags", selections: Binding<Set<String>>, options: [String], buttonHeight: CGFloat = 36, showsActiveSelections: Bool = true) {
        self.title = title
        _selections = selections
        self.options = options
        self.buttonHeight = buttonHeight
        self.showsActiveSelections = showsActiveSelections
    }

    private var filteredOptions: [String] {
        let query = RecipeTagPolicy.clean(query)
        return query.isEmpty ? options : options.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isPresented = true } label: {
                Text(selections.isEmpty ? title : "\(title) (\(selections.count))")
                    .font(.subheadline.weight(.medium)).foregroundStyle(selections.isEmpty ? AppTheme.label : AppTheme.primary)
                    .padding(.horizontal, 12).frame(height: buttonHeight).background(AppTheme.input)
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
            if showsActiveSelections, !selections.isEmpty {
                TagFlowLayout {
                    ForEach(selections.sorted(), id: \.self) { tag in
                        RemovableTagChip(title: tag) { selections.remove(tag) }
                    }
                    Button("Clear all") { selections.removeAll() }
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.primary)
                }
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    List {
                        if !selections.isEmpty { Button("Clear all", role: .destructive) { selections.removeAll() } }
                        ForEach(filteredOptions, id: \.self) { tag in
                            Button { toggle(tag) } label: {
                                HStack { Text(tag); Spacer(); Image(systemName: selections.contains(tag) ? "checkmark.circle.fill" : "circle") }
                                    .foregroundStyle(selections.contains(tag) ? AppTheme.primary : AppTheme.text)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Filter \(title)")
                .searchable(text: $query, prompt: "Search \(title.lowercased())")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func toggle(_ tag: String) {
        if selections.contains(tag) { selections.remove(tag) } else { selections.insert(tag) }
    }
}

struct PrimaryButton: View {
    let title: String; var icon: String? = nil; var isLoading = false; let action: () -> Void
    var body: some View { Button(action: action) { Group { if isLoading { ProgressView().tint(.black) } else if let icon { Label(title, systemImage: icon) } else { Text(title) } }.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 48) }.buttonStyle(.borderedProminent).tint(AppTheme.accent).foregroundStyle(.black).accessibilityLabel(isLoading ? "\(title), in progress" : title) }
}

struct RecipeThumbnail: View {
    let recipe: Recipe
    var body: some View {
        Group {
            if let data = recipe.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { LinearGradient(colors: [AppTheme.elevatedSurface, AppTheme.input], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "fork.knife").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent) } }
        }.accessibilityHidden(true)
    }
}

struct InlineErrorBanner: View {
    let message: String; let retry: (() -> Void)?
    var body: some View { HStack(spacing: AppTheme.Spacing.xs) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.warning); Text(message).font(.footnote).foregroundStyle(AppTheme.textPrimary); Spacer(minLength: 0); if let retry { Button("Retry", action: retry).font(.footnote.weight(.semibold)) } }.padding(AppTheme.Spacing.sm).background(AppTheme.elevatedSurface).clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)).accessibilityElement(children: .combine) }
}

/// Shared overlay navigation control for image-led/detail screens.
struct CircularBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(AppTheme.elevatedSurface.opacity(0.96))
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel("Back")
    }
}

struct RecipeSelectionCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 10) {
            RecipeThumbnail(recipe: recipe)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Text(recipe.author)
                    .font(.caption)
                    .foregroundStyle(AppTheme.label)
                if !recipe.tags.isEmpty { TagPreview(tags: recipe.tags) }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }
}

extension View {
    func figmaInput() -> some View {
        self
            .font(.body)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.input)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.control).stroke(AppTheme.separator, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(minHeight: 48)
    }
}
