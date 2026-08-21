import SwiftUI

/// Hero du paywall Premium — logo Poof central + 5 chips features en orbite
/// continue (période 20s, sens horaire, lent et hypnotique). Style monochrome
/// Apple : tout en glass blanc uniforme, pas de couleur par feature.
struct PaywallHeroOrbit: View {
    let features: [PremiumFeature]
    let onTapFeature: (PremiumFeatureKind) -> Void

    private let orbitRadius: CGFloat = 130
    private let period: Double = 20

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = elapsed.truncatingRemainder(dividingBy: period) / period
            let angleOffset = phase * 2 * .pi

            ZStack {
                haloBackground
                orbitGuide
                poofLogo
                    .frame(width: 104, height: 104)

                ForEach(Array(features.enumerated()), id: \.element.id) { idx, feature in
                    let base = 2 * .pi * Double(idx) / Double(features.count)
                    let angle = base + angleOffset - .pi / 2
                    let x = cos(angle) * orbitRadius
                    let y = sin(angle) * orbitRadius

                    OrbitChip(feature: feature) {
                        PoofHaptics.soft()
                        onTapFeature(feature.kind)
                    }
                    .offset(x: x, y: y)
                }
            }
            .frame(width: 340, height: 340)
        }
    }

    // MARK: - Décors

    private var haloBackground: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 180
                )
            )
            .frame(width: 380, height: 380)
            .blur(radius: 10)
    }

    private var orbitGuide: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            .frame(width: orbitRadius * 2, height: orbitRadius * 2)
    }

    private var poofLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)

            Image(systemName: "cloud.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.30), radius: 3, y: 2)
                .offset(x: -3, y: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.30), radius: 2, y: 2)
                .offset(x: 16, y: -14)
        }
    }
}

// MARK: - Chip orbite

private struct OrbitChip: View {
    let feature: PremiumFeature
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.30), radius: 10, y: 4)

                Image(systemName: feature.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
            }
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
