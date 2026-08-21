import SwiftUI

// Atomic design components matching the Figma Tvvo6kXMeIpDj7VGG0KsDW spec.
// Every VStack / HStack declares `spacing: 0` explicitly, and every padding /
// frame is spelled out. No implicit SwiftUI spacing anywhere.

// MARK: - CustomHeader

/// Nav bar row — big bold title on the left, circular avatar button on the right.
/// Height fixed at 48pt (matches the Figma iPhone 17 avatar bounds).
struct CustomHeader: View {
    let title: String
    var onAvatarTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(PoofTokens.title)
                .foregroundColor(PoofTokens.textPrimary)
                .minimumScaleFactor(0.85)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            AvatarButton(action: onAvatarTap)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(height: 62)
    }
}

/// Circular avatar tile — 48×48, filled with the dark blue-grey token
/// (matches the Figma "Button Group" component at 48×48).
struct AvatarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .center) {
                Circle()
                    .fill(PoofTokens.darkTile)
                    .frame(width: 48, height: 48)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(PoofTokens.textPrimary.opacity(0.85))
                    .frame(width: 48, height: 48)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .accessibilityHint("Opens profile and settings")
    }
}

// MARK: - MainCard

/// Big blue card container matching every Figma hero card.
/// Corner radius 32pt, 5-stop non-linear blue gradient, radial highlight,
/// then the full photographic stack: specular hairline (0.33pt) + procedural
/// grain + inner shadow + chromatic rim. Each layer is individually subtle;
/// stacked they take the surface from "flat CSS" to "shot on camera".
struct MainCard<Content: View>: View {
    var height: CGFloat
    var cornerRadius: CGFloat = PoofTokens.radiusCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(mainCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .poofPhotographicSurface(radius: cornerRadius)
            .appleRimHighlight(radius: cornerRadius)
            .appleCardDepth(tint: PoofTokens.cardBlueBottom, intensity: 1.0)
    }

    private var mainCardBackground: some View {
        ZStack {
            // Base 5-stop non-linear gradient (photographed, not linear).
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PoofTheme.heroGradientRich)

            // Off-center radial highlight — mimics the way ambient light lands
            // on a curved glass surface, biased toward the upper-left third.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        center: UnitPoint(x: 0.42, y: 0.32),
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - CardHairline

/// The subtle horizontal white gradient line that separates a card body from
/// its footer (used inside Home MainCard between the Poof glyph and
/// "See subscriptions", and inside Send hero between the icon and the caption).
struct CardHairline: View {
    var body: some View {
        LinearGradient(
            colors: [PoofTokens.hairline, PoofTokens.hairline.opacity(0.28)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 0.6)
    }
}

// MARK: - SectionLabel

/// Left-aligned bold label — "My devices", "Detected nearby".
struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(PoofTokens.sectionLabel)
                .foregroundColor(PoofTokens.textPrimary)
                .minimumScaleFactor(0.9)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
    }
}

// MARK: - SectionContainer

/// Rounded dark-fill container that hosts device bubbles or the
/// "nearby" empty state. Height is caller-defined so the same atom can
/// carry a 156pt bubble row or a 175pt empty block.
struct SectionContainer<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: PoofTokens.radiusCard, style: .continuous)
                .fill(PoofTokens.sectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoofTokens.radiusCard, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6)
                )
                .appleRimHighlight(radius: PoofTokens.radiusCard, top: 0.16, mid: 0.03)
                .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)

            content()
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .frame(height: height)
    }
}

// MARK: - OptionCardRow

/// Row used inside the Send bottom sheet — coloured icon tile on the left,
/// bold title + fine-print description on the right. Fixed at 98pt height
/// (matches the Figma "Rectangle 11 / 12 / 13" components).
struct OptionCardRow: View {
    let icon: String
    let iconSize: CGFloat
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            PoofHaptics.tap()
            action()
        }) {
            HStack(spacing: 16) {
                iconTile

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PoofTokens.headline)
                        .foregroundColor(PoofTokens.textPrimary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(PoofTokens.finePrint)
                        .foregroundColor(PoofTokens.textPrimary.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.65))
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(height: 98)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: PoofTokens.radiusCard, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .appleRimHighlight(radius: PoofTokens.radiusCard, top: 0.26, mid: 0.05)
        }
        .buttonStyle(HeroPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }

    private var iconTile: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: PoofTokens.radiusIcon, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: 56, height: 56)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(PoofTokens.textPrimary)
                .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
    }
}

struct HeroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}
