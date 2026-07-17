import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.13)
    static let muted = Color(red: 0.39, green: 0.43, blue: 0.49)
    static let line = Color(red: 0.86, green: 0.88, blue: 0.91)
    static let accent = Color(red: 0.02, green: 0.38, blue: 0.49)
    static let warning = Color(red: 0.93, green: 0.56, blue: 0.18)
}

struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
