import SwiftUI

/// Remplacement de la paywall payante pendant la période beta. Communique
/// que le Premium est en développement, présente un teaser des features à
/// venir, et met en avant la récompense « 1 mois offert au lancement » si
/// l'utilisateur envoie au moins `PoofBetaCounter.targetCount` fichiers
/// pendant la beta.
struct PremiumComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var counter = PoofBetaCounter.shared

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

    private var background: some View {
        // Même gradient bleu → gris que la home Send + les autres sheets Poof,
        // pour rester cohérent avec l'identité visuelle de l'app.
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

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                hero
                rewardCard
                featuresPreview
                closingNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 80)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.02)
                            ],
                            center: .center, startRadius: 4, endRadius: 60
                        )
                    )
                    .frame(width: 130, height: 130)
                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.35), radius: 12)
            }
            Text(L10n(fr: "Premium arrive bientôt", en: "Premium is coming soon").localized)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(L10n(
                fr: "On finalise chaque feature une par une pour qu'elles soient parfaites au lancement. Aucun achat pour l'instant.",
                en: "We're polishing each feature one by one to launch them perfect. No purchase for now."
            ).localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Reward card (1 mois offert)

    private var rewardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n(fr: "1 mois Premium offert", en: "1 month Premium free").localized)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                    Text(L10n(
                        fr: "Récompense early supporter — automatique au lancement.",
                        en: "Early supporter reward — automatic at launch."
                    ).localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                }
            }

            progressBar

            HStack {
                Text(counter.isUnlocked
                    ? L10n(fr: "Unlocked ✓", en: "Unlocked ✓").localized
                    : L10n(
                        fr: "\(counter.remaining) envoi(s) restants",
                        en: "\(counter.remaining) send(s) to go"
                    ).localized)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(counter.isUnlocked ? .white : .white.opacity(0.85))
                Spacer()
                Text("\(min(counter.sendCount, PoofBetaCounter.targetCount)) / \(PoofBetaCounter.targetCount)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    counter.isUnlocked ? Color.white.opacity(0.55) : Color.white.opacity(0.14),
                    lineWidth: counter.isUnlocked ? 1.4 : 0.6
                )
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * counter.progress))
                    .animation(.spring(response: 0.55, dampingFraction: 0.85), value: counter.progress)
            }
        }
        .frame(height: 10)
    }

    // MARK: - Features preview

    private var featuresPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n(fr: "Ce que tu débloqueras", en: "What you'll unlock").localized)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
            VStack(spacing: 10) {
                ForEach(PoofPremiumCatalog.all) { feature in
                    featureRow(feature)
                }
            }
        }
    }

    private func featureRow(_ feature: PremiumFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(feature.tint.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(feature.tint.opacity(0.55), lineWidth: 0.6)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title.localized)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                Text(feature.baseline.localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            Text(L10n(fr: "Soon", en: "Soon").localized)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }

    // MARK: - Closing note

    private var closingNote: some View {
        Text(L10n(
            fr: "Merci d'être là dès le début. Les premières features Premium sortiront progressivement — tu seras notifié à chaque nouveauté.",
            en: "Thanks for being here from day one. Premium features will ship progressively — you'll be notified for each release."
        ).localized)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    // MARK: - Top bar

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
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}
