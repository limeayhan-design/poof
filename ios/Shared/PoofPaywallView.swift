import SwiftUI

/// Paywall Premium — pattern Apple natif (iCloud+, Apple One, Fitness+).
/// Structure : hero orbit → titre → 5 bénéfices → 3 plans → CTA → footer.
/// Décision utilisateur en 8 secondes, zéro scroll fatigue.
///
/// Toutes les claims sont vérifiées contre le code — aucun chiffre inventé,
/// aucun bénéfice qui n'existe pas :
///  - Devices illimités : PoofTier+Limits.maxPairedDevices Free=1, Premium=nil
///  - Historique illimité : maxHistoryAgeHours Free=24h, Premium=nil
///  - Accusés lecture : canUseReadReceipts = isPremium
///  - Studio : StudioPlatform enum réel (Reels/TikTok/Shorts/LinkedIn)
///  - Offline : OfflineConfig via MultipeerConnectivity (BT + Wi-Fi Direct)
struct PoofPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PoofPremiumStore.shared

    let initialScrollTarget: PremiumFeatureKind?

    init(initialScrollTarget: PremiumFeatureKind? = nil) {
        self.initialScrollTarget = initialScrollTarget
    }

    var body: some View {
        ZStack {
            background
            content
            closeButton
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
    }

    // MARK: - Background — bleu Poof lumineux mais assez profond pour lisibilité

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 74 / 255, green: 148 / 255, blue: 255 / 255),
                Color(red: 50 / 255, green: 90 / 255, blue: 175 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                hero
                    .padding(.top, 8)
                headlineBlock
                trustLine
                benefitsCard
                    .padding(.top, 2)
                plans
                    .padding(.top, 2)
                purchaseCTA
                    .padding(.top, 4)
                subscriptionDisclosure
                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Hero orbit

    // PaywallHeroOrbit fait 340×340 en interne — on scale down pour tenir
    // sur iPhone SE et sheet Mac 480×780 sans clip.

    private var hero: some View {
        PaywallHeroOrbit(
            features: PoofPremiumCatalog.all,
            onTapFeature: { _ in PoofHaptics.soft() }
        )
        .scaleEffect(0.68)
        // scaleEffect ne change PAS la taille de layout — l'orbit garde 340×340
        // en intrinsic size. On fixe une frame plus petite pour que le VStack
        // parent n'étire pas à 340pt de large (débordait sur iPhone SE).
        .frame(width: 240, height: 220)
        .clipped()
    }

    // MARK: - Headline

    private var headlineBlock: some View {
        VStack(spacing: 8) {
            Text(L10n(fr: "Débloque Poof.", en: "Unlock Poof.").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.20), radius: 6, y: 2)

            Text(
                L10n(
                    fr: "Passcode, accusés de lecture, mode hors ligne.",
                    en: "Passcode, read receipts, offline mode."
                ).localized
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
    }

    // MARK: - Trust line (2 anchors 100% factuels)

    private var trustLine: some View {
        HStack(spacing: 10) {
            trustPill(icon: "iphone.and.arrow.forward", text: L10n(fr: "Cross-platform", en: "Cross-platform"))
            trustPill(icon: "hand.raised.slash.fill", text: L10n(fr: "Sans pub", en: "No ads"))
        }
        .frame(maxWidth: .infinity)
    }

    private func trustPill(icon: String, text: L10n) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text.localized)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    // MARK: - Benefits card (glass container avec 5 rows)

    private var benefitsCard: some View {
        VStack(spacing: 12) {
            benefitRow(
                icon: "lock.shield.fill",
                title: L10n(fr: "Sécurité renforcée", en: "Enhanced security"),
                subtitle: L10n(fr: "Passcode, expiration, Face ID.", en: "Passcode, expiry, Face ID.")
            )
            divider
            benefitRow(
                icon: "eye.fill",
                title: L10n(fr: "Accusés de lecture", en: "Read receipts"),
                subtitle: L10n(fr: "Sache qui ouvre tes fichiers.", en: "Know who opens your files.")
            )
            divider
            benefitRow(
                icon: "laptopcomputer.and.iphone",
                title: L10n(fr: "Devices illimités", en: "Unlimited devices"),
                subtitle: L10n(fr: "iPhone, iPad, Mac sans limite.", en: "iPhone, iPad, Mac, no limit.")
            )
            divider
            benefitRow(
                icon: "airplane",
                title: L10n(fr: "Mode hors ligne", en: "Offline mode"),
                subtitle: L10n(
                    fr: "Bluetooth ou Wi-Fi Direct, sans internet.",
                    en: "Bluetooth or Wi-Fi Direct, no internet."
                )
            )
            divider
            benefitRow(
                icon: "film.fill",
                title: L10n(fr: "Studio créateur", en: "Creator studio"),
                subtitle: L10n(fr: "Pré-encode Reels, TikTok, Shorts.", en: "Pre-encode Reels, TikTok, Shorts.")
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 0.5)
    }

    private func benefitRow(icon: String, title: L10n, subtitle: L10n) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle.localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plans (glass cards)

    private var plans: some View {
        VStack(spacing: 10) {
            planCard(.yearly, highlight: true)
            planCard(.lifetime, highlight: false)
            planCard(.monthly, highlight: false)
        }
    }

    private func planCard(_ plan: PoofPremiumPlan, highlight: Bool) -> some View {
        let isSelected = store.selectedPlan == plan
        return Button {
            PoofHaptics.tap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                store.selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                selectionDot(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(planTitle(plan))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if highlight {
                            Text(L10n(fr: "SAVE 42%", en: "SAVE 42%").localized)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                    Text(planSubtitle(plan))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(store.displayPrice(for: plan) ?? plan.fallbackPriceLabel)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if let equiv = plan.monthlyEquivalent {
                        Text(equiv)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white : Color.clear,
                        lineWidth: isSelected ? 1.8 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ plan: PoofPremiumPlan) -> String {
        // Title inclut la durée pour compliance Apple Guideline 3.1.2(c)
        // "Title of auto-renewing subscription" doit être clair sur la length.
        switch plan {
        case .monthly: L10n(fr: "Poof Premium — 1 mois", en: "Poof Premium — 1 Month").localized
        case .yearly: L10n(fr: "Poof Premium — 1 an", en: "Poof Premium — 1 Year").localized
        case .lifetime: L10n(fr: "Poof Premium — À vie", en: "Poof Premium — Lifetime").localized
        }
    }

    private func planSubtitle(_ plan: PoofPremiumPlan) -> String {
        switch plan {
        case .monthly: L10n(fr: "Abonnement mensuel · essai 7 jours", en: "Monthly subscription · 7-day free trial").localized
        case .yearly: L10n(fr: "Abonnement annuel · essai 7 jours", en: "Yearly subscription · 7-day free trial").localized
        case .lifetime: L10n(fr: "Paiement unique · pas d'abonnement", en: "One-time payment · no subscription").localized
        }
    }

    private func selectionDot(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(isSelected ? 1 : 0.4), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .transition(.scale)
            }
        }
    }

    // MARK: - CTA (blanc solide — pattern Apple)

    private var purchaseCTA: some View {
        VStack(spacing: 10) {
            Button {
                PoofHaptics.impactMedium()
                Task {
                    await store.purchase(store.selectedPlan)
                    if store.isPremium {
                        PoofHaptics.success()
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isPurchasing {
                        ProgressView().tint(.black)
                    }
                    Text(ctaLabel)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white)
                )
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing || store.isLoadingProducts)

            Text(subCTALine)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ctaLabel: String {
        if store.selectedPlan == .lifetime {
            return L10n(fr: "Débloquer à vie", en: "Unlock forever").localized
        }
        if store.isEligibleForIntro {
            return L10n(fr: "Essayer 7 jours gratuits", en: "Try 7 days free").localized
        }
        return L10n(fr: "Continuer", en: "Continue").localized
    }

    private var subCTALine: String {
        let price = store.displayPrice(for: store.selectedPlan) ?? store.selectedPlan.fallbackPriceLabel
        if store.selectedPlan == .lifetime {
            return L10n(
                fr: "\(price) une fois. Aucun abonnement.",
                en: "\(price) once. No subscription."
            ).localized
        }
        if store.isEligibleForIntro {
            return L10n(
                fr: "Puis \(price). Annule à tout moment.",
                en: "Then \(price). Cancel anytime."
            ).localized
        }
        return L10n(
            fr: "\(price). Annule à tout moment.",
            en: "\(price). Cancel anytime."
        ).localized
    }

    // MARK: - Subscription disclosure (Apple Guideline 3.1.2(c) requirement)
    // Boilerplate obligatoire pour tout paywall abo auto-renew.
    private var subscriptionDisclosure: some View {
        Text(L10n(
            fr: "Abonnement à renouvellement automatique. Le paiement est prélevé sur votre compte Apple à la confirmation de l'achat. L'abonnement se renouvelle automatiquement sauf s'il est annulé au moins 24 heures avant la fin de la période en cours. Vous pouvez gérer et annuler vos abonnements dans les réglages de votre compte App Store après l'achat.",
            en: "Auto-renewable subscription. Payment will be charged to your Apple Account at confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase."
        ).localized)
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            footerLink(L10n(fr: "Restaurer", en: "Restore")) {
                Task { await store.restore() }
            }
            Text("·").foregroundColor(.white.opacity(0.4))
            footerExternal(L10n(fr: "Conditions d'utilisation (EULA)", en: "Terms of Use (EULA)"), url: "https://poof.app/terms")
            Text("·").foregroundColor(.white.opacity(0.4))
            footerExternal(L10n(fr: "Confidentialité", en: "Privacy"), url: "https://poof.app/privacy")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.65))
    }

    private func footerLink(_ text: L10n, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text.localized)
        }
        .buttonStyle(.plain)
    }

    private func footerExternal(_ text: L10n, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(text.localized)
        }
    }

    // MARK: - Close

    private var closeButton: some View {
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
                        .frame(width: 34, height: 34)
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}

#Preview {
    PoofPaywallView()
}
