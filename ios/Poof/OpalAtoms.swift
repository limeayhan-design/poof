import SwiftUI

// Atomes Opal — briques de base pour la refonte des écrans.
// Chaque atome respecte strictement le brand kit Opal (brandkit.opal.so).

// MARK: - OpalCard

/// Card standard Opal — dark gray surface `#3A3A3A` sur fond noir.
/// 95% des cards de l'app doivent utiliser ce composant.
struct OpalCard<Content: View>: View {
    var padding: CGFloat = OpalTokens.space20
    var radius: CGFloat = OpalTokens.radiusCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OpalTokens.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - OpalMilestoneCard

/// Card milestone Opal — gradient coloré réservé aux moments de célébration.
/// À utiliser UNIQUEMENT pour : pairing réussi, fichier envoyé, tier upgrade, streak.
/// Jamais comme background par défaut.
struct OpalMilestoneCard<Content: View>: View {
    enum Kind {
        case welcome, connection, achievement, celebration, streak

        var gradient: LinearGradient {
            switch self {
            case .welcome: OpalTokens.gradientWelcome
            case .connection: OpalTokens.gradientConnection
            case .achievement: OpalTokens.gradientAchievement
            case .celebration: OpalTokens.gradientCelebration
            case .streak: OpalTokens.gradientStreak
            }
        }
    }

    var kind: Kind
    var padding: CGFloat = OpalTokens.space24
    var radius: CGFloat = OpalTokens.radiusCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(kind.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.7)
            )
    }
}

// MARK: - OpalGradientText

/// Texte avec le gradient signature Opal (gris → blanc).
/// Pour les gros titres ambient de la Home / hero sections.
struct OpalGradientText: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(OpalTokens.headline(size: size))
            .tracking(size * OpalTokens.trackingBold)
            .foregroundStyle(OpalTokens.textGradient)
    }
}

// MARK: - OpalTitle

/// Titre bold blanc — H1/H2 de l'app.
struct OpalTitle: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(OpalTokens.headline(size: size))
            .tracking(size * OpalTokens.trackingBold)
            .foregroundColor(OpalTokens.textPrimary)
    }
}

// MARK: - OpalBody

/// Body medium gris `#BCBBC0` — text principal des paragraphes.
struct OpalBody: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(OpalTokens.body(size: size))
            .foregroundColor(OpalTokens.textSecondary)
    }
}

// MARK: - OpalMetric

/// Gros nombre ambient (light weight, opacité 70%) — pour metrics de home.
/// Ex : "2h 34m" screen time, "82%" focus score.
struct OpalMetric: View {
    let value: String
    var size: CGFloat = 56

    var body: some View {
        Text(value)
            .font(OpalTokens.ambient(size: size))
            .tracking(size * OpalTokens.trackingAmbient)
            .foregroundColor(OpalTokens.textPrimary.opacity(OpalTokens.ambientOpacity))
    }
}
