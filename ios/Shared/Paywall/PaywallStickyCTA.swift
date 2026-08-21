import SwiftUI

/// CTA sticky en bas de la paywall — card glass qui reste visible pendant tout
/// le scroll. Toggle mensuel / annuel, prix localisés (StoreKit),
/// label conditionnel selon éligibilité intro offer.
struct PaywallStickyCTA: View {
    @Binding var selectedPlan: PoofPremiumPlan
    let displayPrice: (PoofPremiumPlan) -> String
    let isEligibleForIntro: Bool
    let isLoadingProducts: Bool
    let isPurchasing: Bool
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            planPicker
            purchaseButton
            footerLine
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        HStack(spacing: 10) {
            ForEach(PoofPremiumPlan.allCases) { plan in
                planTile(plan)
            }
        }
    }

    private func planTile(_ plan: PoofPremiumPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            PoofHaptics.soft()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedPlan = plan
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(planTitle(plan))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                    if plan == .yearly {
                        Text(L10n(fr: "Populaire", en: "Popular").localized)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white))
                    }
                }
                Text(displayPrice(plan))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.white)
                Text(plan.billedLabel.localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.14),
                        lineWidth: isSelected ? 1.5 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ plan: PoofPremiumPlan) -> String {
        switch plan {
        case .monthly: L10n(fr: "Mensuel", en: "Monthly").localized
        case .yearly: L10n(fr: "Annuel", en: "Yearly").localized
        }
    }

    // MARK: - Purchase button

    private var purchaseButton: some View {
        Button {
            PoofHaptics.impactMedium()
            onPurchase()
        } label: {
            ZStack {
                if isPurchasing || isLoadingProducts {
                    ProgressView().tint(.black)
                } else {
                    Text(ctaLabel)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: .white.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || isLoadingProducts)
    }

    /// Label conditionnel : "Essayer 7 jours gratuits" si l'utilisateur n'a
    /// jamais consommé l'intro offer, sinon "Continuer avec Premium".
    private var ctaLabel: String {
        if isEligibleForIntro {
            return L10n(fr: "Essayer 7 jours gratuits", en: "Try 7 days free").localized
        }
        return L10n(fr: "Continuer avec Premium", en: "Continue with Premium").localized
    }

    // MARK: - Footer (restore + legal)

    private var footerLine: some View {
        HStack(spacing: 14) {
            Button {
                onRestore()
            } label: {
                Text(L10n(fr: "Restaurer mes achats", en: "Restore purchases").localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Text("·")
                .foregroundColor(.white.opacity(0.4))

            Text(legalLine)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legalLine: String {
        let price = displayPrice(selectedPlan)
        if isEligibleForIntro {
            return L10n(
                fr: "Ensuite \(price). Sans engagement, résiliation à tout moment.",
                en: "Then \(price). No commitment, cancel anytime."
            ).localized
        }
        return L10n(
            fr: "\(price). Sans engagement, résiliation à tout moment.",
            en: "\(price). No commitment, cancel anytime."
        ).localized
    }
}
