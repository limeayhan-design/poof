import SwiftUI

// Pricing modal — refonte langage Ripples.
// 2 tiers visibles: Standard (free, teal) + Premium (violet, hero).
// Bandeau rouge loss-aversion en haut. Trust proof factuel en bas
// (E2E · No cloud · Open · P2P) — pas de social proof faux (App Store safe).

struct PricingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue
    @State private var isYearly = true

    private var currentTier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RipplesTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    lossAversionBanner
                    standardCard
                    premiumCard
                    trustProof
                }
                .padding(.horizontal, 16)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }

            RipplesHeaderButton(systemName: "xmark") { dismiss() }
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Choose your plan")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Text("Zero cloud. End-to-end encrypted. On every tier.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Loss aversion (rouge)

    private var lossAversionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 2)
            Text("Without Premium, Poof is Wi-Fi only, capped to 1 paired device, and forgets your history after 24h.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#B23434"))
        )
    }

    // MARK: - Standard (teal)

    private var standardCard: some View {
        let isCurrent = currentTier == .free
        return RipplesCard(background: RipplesTokens.tealBG) {
            VStack(alignment: .leading, spacing: 16) {
                cardTopRow(
                    icon: "sparkles",
                    title: "Standard",
                    priceLabel: "Free",
                    accent: RipplesTokens.tealAccent
                )

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(standardFeatures, id: \.text) { f in
                        featureRow(f, accent: RipplesTokens.tealAccent)
                    }
                }

                selectButton(
                    label: isCurrent ? "Current plan" : "Switch to Standard",
                    isCurrent: isCurrent,
                    action: { switchTo(.free) }
                )
            }
        }
    }

    // MARK: - Premium (violet, hero)

    private var premiumCard: some View {
        let isCurrent = currentTier == .premium
        let priceLabel = isYearly ? "€39.99/yr" : "€4.99/mo"
        let ctaLabel = isYearly
            ? "Start 7-day free trial · €39.99/yr"
            : "Start 7-day free trial · €4.99/mo"

        return RipplesCard(background: RipplesTokens.violetBG) {
            VStack(alignment: .leading, spacing: 20) {
                cardTopRow(
                    icon: "star.circle.fill",
                    title: "Premium",
                    priceLabel: priceLabel,
                    accent: RipplesTokens.violetAccent
                )

                billingToggle

                pillar(
                    icon: "bolt.fill",
                    title: "Unlimited",
                    features: [
                        .init(text: "Unlimited paired devices"),
                        .init(text: "Whole folders in one drag"),
                        .init(text: "Full history + preview")
                    ]
                )

                pillar(
                    icon: "globe",
                    title: "Everywhere",
                    features: [
                        .init(text: "Works beyond your Wi-Fi (P2P internet)"),
                        .init(text: "Universal Clipboard (text + files)"),
                        .init(text: "iOS · macOS · Windows · Linux")
                    ]
                )

                pillar(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic",
                    features: [
                        .init(text: "Read receipts + delivery status"),
                        .init(text: "Live Activity while transferring"),
                        .init(text: "Siri Shortcuts integration")
                    ]
                )

                selectButton(
                    label: isCurrent ? "Current plan" : ctaLabel,
                    isCurrent: isCurrent,
                    action: { switchTo(.premium) }
                )
            }
        }
    }

    // MARK: - Reusable subviews

    private func cardTopRow(
        icon: String,
        title: String,
        priceLabel: String,
        accent: Color
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Text(priceLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    private var billingToggle: some View {
        HStack(spacing: 6) {
            toggleOption(label: "Monthly", selected: !isYearly) { isYearly = false }
            toggleOption(label: "Yearly · Save 33%", selected: isYearly) { isYearly = true }
        }
        .padding(4)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
    }

    private func toggleOption(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .black : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func pillar(icon: String, title: String, features: [Feature]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(RipplesTokens.violetAccent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(RipplesTokens.violetAccent)
            }
            ForEach(features, id: \.text) { f in
                featureRow(f, accent: RipplesTokens.violetAccent)
            }
        }
        .padding(.top, 6)
    }

    private func featureRow(_ f: Feature, accent: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
            Text(f.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            if f.soon {
                Text("SOON")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(accent)
                    )
            }
            Spacer(minLength: 0)
        }
    }

    private func selectButton(
        label: String,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            PoofHaptics.tap()
            action()
        }) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isCurrent ? .white.opacity(0.5) : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule().fill(isCurrent
                        ? Color.white.opacity(0.08)
                        : Color.white)
                )
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    // MARK: - Trust proof (bas — remplace social proof)

    private var trustProof: some View {
        HStack(spacing: 0) {
            trustItem(icon: "lock.fill", label: "E2E")
            trustItem(icon: "xmark.icloud.fill", label: "No cloud")
            trustItem(icon: "globe", label: "Open")
            trustItem(icon: "bolt.fill", label: "P2P")
        }
        .padding(.top, 16)
    }

    private func trustItem(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func switchTo(_ tier: PoofTier) {
        withAnimation(.easeInOut(duration: 0.3)) {
            tierRaw = tier.rawValue
        }
    }

    // MARK: - Data

    private struct Feature {
        let text: String
        var soon: Bool = false
    }

    private var standardFeatures: [Feature] {
        [
            .init(text: "1 paired device"),
            .init(text: "Local network only (Wi-Fi)"),
            .init(text: "Unlimited file size"),
            .init(text: "Unlimited transfers"),
            .init(text: "24h history"),
            .init(text: "Zero ads · zero tracking")
        ]
    }
}
