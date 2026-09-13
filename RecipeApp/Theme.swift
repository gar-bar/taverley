import SwiftUI

enum AppTheme {
    static let background = Color(red: 15/255, green: 13/255, blue: 20/255)
    static let surface = Color(red: 27/255, green: 23/255, blue: 36/255)
    static let input = Color(red: 46/255, green: 39/255, blue: 59/255)
    static let border = Color(red: 57/255, green: 48/255, blue: 72/255)
    static let primary = Color(red: 196/255, green: 142/255, blue: 255/255)
    static let mealIndicator = Color(red: 92/255, green: 52/255, blue: 127/255)
    static let text = Color(red: 244/255, green: 238/255, blue: 247/255)
    static let label = Color(red: 163/255, green: 155/255, blue: 174/255)
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(14).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12)) }
}

struct Tag: View {
    let title: String
    var body: some View { Text(title).font(.caption2.weight(.medium)).foregroundStyle(AppTheme.text).padding(.horizontal, 9).padding(.vertical, 5).background(AppTheme.input).clipShape(Capsule()) }
}

struct PrimaryButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    var body: some View { Button(action: action) { Group { if let icon { Label(title, systemImage: icon) } else { Text(title) } }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13).background(AppTheme.primary).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 12)) } }
}

extension View {
    func figmaInput() -> some View {
        self.font(.custom("Inter", size: 16)).foregroundStyle(AppTheme.text).padding(.horizontal, 12).padding(.vertical, 10).background(AppTheme.input).overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12)).frame(minWidth: 0, maxWidth: .infinity).frame(height: 44)
    }
}
