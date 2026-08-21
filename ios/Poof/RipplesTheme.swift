import SwiftUI

// Ripples design system — extrait de l'app "Habit Tracker - Ripples"
// (Mykola Harmash). Signature visuelle: fond noir pur, cards teintées
// (teal / bleu / violet), boutons capsule blanc cassé.
// Coexiste avec Opal et PoofTheme pendant la migration.

enum RipplesTokens {
    // MARK: - Background

    static let background = Color(hex: "#000000")

    // MARK: - Header buttons (dark gray circles)

    static let headerButtonBG = Color(hex: "#1C1C1E")

    // MARK: - Card palettes (each card = 1 color theme)

    /// Teal — "How Poof works"
    static let tealBG = Color(hex: "#0A2A26")
    static let tealAccent = Color(hex: "#4DD4B8")

    /// Blue — "Your transfers"
    static let blueBG = Color(hex: "#0F1929")
    static let blueAccent = Color(hex: "#5D8FF0")

    /// Violet — "Poof everywhere"
    static let violetBG = Color(hex: "#1A1230")
    static let violetAccent = Color(hex: "#7B65E8")

    // MARK: - CTA capsule

    static let ctaBG = Color(hex: "#EEF5F0")
    static let ctaText = Color.black

    // MARK: - Text

    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.6)

    // MARK: - Typography

    static func title(size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func cardTitle(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func cta(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func stepLabel(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    // MARK: - Spacing / radius

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 20
    static let ctaHeight: CGFloat = 52
    static let headerButtonSize: CGFloat = 44
}
