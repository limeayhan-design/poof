import SwiftUI

// Ripples atoms — briques de base pour composer les écrans style Ripples.
// Card teintée + header buttons + CTA capsule + 3-step visualization.

// MARK: - RipplesHeaderButton

/// Bouton rond gris foncé pour le header (menu, add, close).
struct RipplesHeaderButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(RipplesTokens.textPrimary)
                .frame(
                    width: RipplesTokens.headerButtonSize,
                    height: RipplesTokens.headerButtonSize
                )
                .background(Circle().fill(RipplesTokens.headerButtonBG))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RipplesCard

/// Card teintée style Ripples — fond sombre coloré, contenu à composer.
struct RipplesCard<Content: View>: View {
    var background: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(RipplesTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: RipplesTokens.cardRadius,
                    style: .continuous
                )
                .fill(background)
            )
    }
}

// MARK: - RipplesCTAButton

/// Bouton capsule blanc cassé avec cercle radio à gauche, texte noir.
struct RipplesCTAButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(RipplesTokens.ctaText)
                Text(title)
                    .font(RipplesTokens.cta())
                    .foregroundColor(RipplesTokens.ctaText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: RipplesTokens.ctaHeight)
            .background(
                Capsule().fill(RipplesTokens.ctaBG)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RipplesStepRow

/// Visualisation en N étapes avec flèches (Pair → Select → Poof).
struct RipplesStepRow: View {
    struct Step {
        let systemName: String
        let label: String
    }

    let steps: [Step]
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                stepView(step)
                if idx < steps.count - 1 {
                    arrow
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func stepView(_ step: Step) -> some View {
        VStack(spacing: 10) {
            Image(systemName: step.systemName)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(accent.opacity(0.15))
                )
            Text(step.label)
                .font(RipplesTokens.stepLabel())
                .foregroundColor(RipplesTokens.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(RipplesTokens.textSecondary.opacity(0.4))
    }
}

// MARK: - RipplesValueGrid

/// Grille 2×2 de "value cells" — icône tinted + label court.
/// Utilisé pour présenter 4 valeurs/piliers d'une app.
struct RipplesValueGrid: View {
    struct Value {
        let systemName: String
        let label: String
    }

    let values: [Value]
    let accent: Color

    var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                valueCell(v)
            }
        }
    }

    private func valueCell(_ v: Value) -> some View {
        HStack(spacing: 10) {
            Image(systemName: v.systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(accent.opacity(0.15))
                )
            Text(v.label)
                .font(RipplesTokens.stepLabel(size: 14))
                .foregroundColor(RipplesTokens.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - RipplesIconRow

/// Row horizontale d'icônes tinted + labels (sans flèches).
/// Utilisé pour lister N items équivalents (plateformes, options, tags).
struct RipplesIconRow: View {
    struct Item {
        let systemName: String
        let label: String
    }

    let items: [Item]
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                itemView(item)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func itemView(_ item: Item) -> some View {
        VStack(spacing: 10) {
            Image(systemName: item.systemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(accent.opacity(0.15))
                )
            Text(item.label)
                .font(RipplesTokens.stepLabel())
                .foregroundColor(RipplesTokens.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
