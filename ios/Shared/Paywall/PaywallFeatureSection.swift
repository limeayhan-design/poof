import SwiftUI

/// Section deep-dive d'une feature Premium — style Apple / monochrome.
/// Icône dans un badge glass blanc uniforme + baseline + 8 promesses en checklist.
/// Une instance par feature (5 dans la paywall).
struct PaywallFeatureSection: View {
    let feature: PremiumFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            iconBadge

            VStack(alignment: .leading, spacing: 8) {
                Text(feature.title.localized)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(feature.baseline.localized)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(Array(feature.promises.enumerated()), id: \.offset) { index, promise in
                    promiseRow(promise.localized, isSoon: feature.soonIndices.contains(index))
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Sub views

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                )

            Image(systemName: feature.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func promiseRow(_ text: String, isSoon: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if isSoon {
                soonBadge
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
    }

    private var soonBadge: some View {
        Text(L10n(fr: "Soon", en: "Soon").localized)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.18))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6))
            )
    }
}
