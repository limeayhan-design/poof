import SwiftUI

// Design tokens matching the PWA (pc/style.css). Dark background, glass surfaces, violet accents.

enum PoofTheme {
    // Background palette
    static let bgBase   = Color(red: 0.043, green: 0.043, blue: 0.078)   // ~#0B0B14
    static let bgTop    = Color(red: 0.078, green: 0.075, blue: 0.157)   // ~#141328
    static let bgBottom = Color(red: 0.031, green: 0.031, blue: 0.055)   // ~#08080E

    // Accents
    static let accent   = Color(red: 0.545, green: 0.494, blue: 1.0)     // #8B7EFF violet
    static let accent2  = Color(red: 0.357, green: 0.545, blue: 1.0)     // #5B8BFF blue
    static let green    = Color(red: 0.247, green: 0.749, blue: 0.498)   // #3FBF7F
    static let danger   = Color(red: 1.0,   green: 0.231, blue: 0.188)   // #FF3B30
    static let dropStroke = Color(red: 0.0, green: 0.717, blue: 1.0)     // #00B7FF

    // Text
    static let textPrimary   = Color.white.opacity(0.98)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary  = Color.white.opacity(0.48)

    // Surfaces
    static let glassFill    = Color.white.opacity(0.06)
    static let glassFillHi  = Color.white.opacity(0.10)
    static let glassStroke  = Color.white.opacity(0.14)

    // Radii + spacing
    static let radiusLg: CGFloat = 22
    static let radiusMd: CGFloat = 16
    static let radiusSm: CGFloat = 12
}

// MARK: - Background

struct PoofBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PoofTheme.bgTop, PoofTheme.bgBase, PoofTheme.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [PoofTheme.accent.opacity(0.20), .clear],
                center: .init(x: 0.2, y: 0.12), startRadius: 20, endRadius: 340
            )
            RadialGradient(
                colors: [PoofTheme.accent2.opacity(0.16), .clear],
                center: .init(x: 0.85, y: 0.85), startRadius: 20, endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass card modifier

struct GlassCard: ViewModifier {
    var radius: CGFloat = PoofTheme.radiusMd
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PoofTheme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [PoofTheme.glassStroke, .white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = PoofTheme.radiusMd) -> some View {
        modifier(GlassCard(radius: radius))
    }
}
