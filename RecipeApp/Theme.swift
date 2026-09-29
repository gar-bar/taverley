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
                HStack(spacing: 6) {
                    ForEach(recipe.tags.prefix(2), id: \.self) { Tag(title: $0) }
                }
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
