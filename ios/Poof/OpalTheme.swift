import SwiftUI

// Design system Opal — extrait du brand kit officiel (brandkit.opal.so).
// Palette noire/blanche pour 95% de l'app, 5 gradients réservés aux moments
// milestones (pairing réussi, fichier envoyé, tier upgrade, streak).
// Ne remplace pas PoofTheme — coexiste pendant la migration écran par écran.

enum OpalTokens {
    // MARK: - Core palette (95% de l'app)

    static let background = Color(hex: "#000000")
    static let textPrimary = Color(hex: "#FFFFFF")
    static let textSecondary = Color(hex: "#BCBBC0")
    static let surface = Color(hex: "#3A3A3A")

    static let textGradient = LinearGradient(
        colors: [Color(hex: "#BCBBC0"), Color(hex: "#FFFFFF")],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: - Milestone gradients (5% — jamais en background)

    /// Violet → Mint. Welcome, onboarding, first success.
    static let gradientWelcome = LinearGradient(
        colors: [Color(hex: "#E2C9FF"), Color(hex: "#8CFFDD")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Ice blue → Violet. Device paired, connection established.
    static let gradientConnection = LinearGradient(
        colors: [Color(hex: "#A9CBFF"), Color(hex: "#B39AFF")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Lime → Cyan. File sent, transfer complete, achievement.
    static let gradientAchievement = LinearGradient(
        colors: [Color(hex: "#D4FF9C"), Color(hex: "#9EF9FF")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Rose → Yellow. Tier upgrade, subscription started.
    static let gradientCelebration = LinearGradient(
        colors: [Color(hex: "#EDC9F2"), Color(hex: "#EDFF4A")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Violet → Peach. Streak, recurring milestone.
    static let gradientStreak = LinearGradient(
        colors: [Color(hex: "#ECB8FF"), Color(hex: "#FFD6AA")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Typography (SF Pro Text, weights per brand kit)

    static func headline(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func subheadline(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func caption(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func ambient(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .light, design: .default)
    }

    // MARK: - Tracking (letter-spacing multipliers, brand kit values)

    static let trackingBold: CGFloat = -0.04
    static let trackingSemibold: CGFloat = -0.02
    static let trackingAmbient: CGFloat = -0.02

    // MARK: - Spacing (harmonic scale)

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48
    static let space56: CGFloat = 56

    // MARK: - Radius

    static let radiusCard: CGFloat = 24
    static let radiusButton: CGFloat = 14
    static let radiusSmall: CGFloat = 10

    // MARK: - Ambient display opacity

    static let ambientOpacity: Double = 0.70
}
