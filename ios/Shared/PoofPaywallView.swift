import SwiftUI

/// Paywall Premium fullscreen — signature de l'app Poof.
/// Ouverte au tap sur `premiumGlassBar` dans la Send view. Structure verticale :
/// hero orbite → intro → loss aversion → 5 sections deep-dive → comparatif →
/// FAQ. Sticky CTA glass en overlay bas. Close button en overlay haut-droite.
struct PoofPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PoofPremiumStore.shared

    /// Feature ciblée par l'ouverture — auto-scroll vers sa section deep-dive
    /// juste après l'apparition. Nil = ouverture standard sur le hero orbite.
    let initialScrollTarget: PremiumFeatureKind?

    init(initialScrollTarget: PremiumFeatureKind? = nil) {
        self.initialScrollTarget = initialScrollTarget
    }

    var body: some View {
        ZStack {
            background
            content
            topBar
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
    }

    // MARK: - Background

    /// Même gradient que PoofSendView — cohérence visuelle bout-en-bout.
    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Scrollable content

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 36) {
                    hero(proxy: proxy)
                    intro
                    lossAversion
                    ForEach(PoofPremiumCatalog.all) { feature in
                        PaywallFeatureSection(feature: feature)
                            .id(feature.kind.id)
                    }
                    compareBlock
                    faqBlock
                    ctaBlock
                }
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
            .onAppear {
                guard let target = initialScrollTarget else { return }
                // Petit délai pour laisser le sheet se poser avant de scroller.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func hero(proxy: ScrollViewProxy) -> some View {
        PaywallHeroOrbit(features: PoofPremiumCatalog.all) { kind in
            withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                proxy.scrollTo(kind.id, anchor: .top)
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(spacing: 10) {
            Text(
                L10n(
                    fr: "30 promesses. 5 pouvoirs.\nUn seul prix.",
                    en: "30 promises. 5 powers.\nOne price."
                ).localized
            )
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                L10n(
                    fr: "Poof Premium débloque tout ce que l'app peut faire — sécurité, contrôle, vitesse, offline et studio créateur.",
                    en: "Poof Premium unlocks everything the app can do — security, control, speed, offline and creator studio."
                ).localized
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Loss aversion banner

    private var lossAversion: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 2)
            Text(
                L10n(
                    fr: "Sans Premium, tu es limité à 500 Mo par fichier, tu n'as pas d'accusé de lecture, et l'envoi hors ligne est désactivé.",
                    en: "Without Premium, you're capped at 500 MB per file, no read receipts, and offline sending is off."
                ).localized
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Compare / FAQ blocks

    private var compareBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                L10n(fr: "Gratuit ou Premium", en: "Free or Premium").localized
            )
            PaywallCompareTable()
        }
    }

    private var faqBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                L10n(fr: "Questions fréquentes", en: "Frequent questions").localized
            )
            PaywallFAQ()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
    }

    // MARK: - Top bar (close)

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    PoofHaptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(Color.black.opacity(0.45))
                        )
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }

    // MARK: - CTA (dernier bloc du scroll)

    private var ctaBlock: some View {
        PaywallStickyCTA(
            selectedPlan: $store.selectedPlan,
            displayPrice: { store.displayPrice(for: $0) },
            isEligibleForIntro: store.isEligibleForIntro,
            isLoadingProducts: store.isLoadingProducts,
            isPurchasing: store.isPurchasing,
            onPurchase: {
                Task {
                    await store.purchase(store.selectedPlan)
                    if store.isPremium {
                        PoofHaptics.success()
                        dismiss()
                    }
                }
            },
            onRestore: {
                Task { await store.restore() }
            }
        )
    }
}

#Preview {
    PoofPaywallView()
}
