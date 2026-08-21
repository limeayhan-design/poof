import SwiftUI

/// FAQ paywall — tue les objections courantes qui bloquent la conversion.
/// Items expandables (tap → dépliage animé). Copy validée pour App Store
/// (mentions cancellation, restauration, cross-platform, trial explicite).
struct PaywallFAQ: View {
    struct Item: Identifiable {
        let id = UUID()
        let question: L10n
        let answer: L10n
    }

    static let items: [Item] = [
        Item(
            question: L10n(
                fr: "Comment fonctionne l'essai gratuit ?",
                en: "How does the free trial work?"
            ),
            answer: L10n(
                fr: "Tu essaies Premium pendant 7 jours, sans limite d'usage. Annule à tout moment depuis les Réglages avant la fin — tu ne paies rien.",
                en: "You get 7 days of full Premium access. Cancel anytime in Settings before day 7 and you won't be charged."
            )
        ),
        Item(
            question: L10n(
                fr: "Puis-je annuler à tout moment ?",
                en: "Can I cancel anytime?"
            ),
            answer: L10n(
                fr: "Oui. Depuis Réglages iOS ou macOS → Ton compte Apple → Abonnements → Poof Premium. Aucune question posée, effet immédiat à la fin de la période payée.",
                en: "Yes. Settings on iOS or macOS → your Apple account → Subscriptions → Poof Premium. No questions asked, takes effect at the end of the paid period."
            )
        ),
        Item(
            question: L10n(
                fr: "Premium marche sur mes autres appareils ?",
                en: "Does Premium work on my other devices?"
            ),
            answer: L10n(
                fr: "Oui. Un seul achat couvre iPhone, iPad et Mac connectés au même identifiant Apple. Partage familial supporté (jusqu'à 5 personnes).",
                en: "Yes. One purchase covers iPhone, iPad and Mac tied to the same Apple ID. Family Sharing supported (up to 5 people)."
            )
        ),
        Item(
            question: L10n(
                fr: "Le cross-platform reste gratuit ?",
                en: "Is cross-platform still free?"
            ),
            answer: L10n(
                fr: "Oui. Envoyer entre iOS, macOS, Android et Windows reste 100 % gratuit — Premium ajoute les features avancées, jamais la connectivité de base.",
                en: "Yes. Sending between iOS, macOS, Android and Windows stays 100% free — Premium adds advanced features, never gates basic connectivity."
            )
        ),
        Item(
            question: L10n(
                fr: "Comment restaurer mon achat ?",
                en: "How do I restore my purchase?"
            ),
            answer: L10n(
                fr: "Tape sur \"Restaurer mes achats\" en bas de cet écran. Le statut Premium est réactivé instantanément.",
                en: "Tap \"Restore purchases\" at the bottom of this screen. Your Premium status is restored instantly."
            )
        ),
        Item(
            question: L10n(
                fr: "Mes données sont vraiment privées ?",
                en: "Is my data actually private?"
            ),
            answer: L10n(
                fr: "Oui. Poof chiffre chaque envoi en AES-256 côté client. Les serveurs ne voient jamais le contenu — même les métadonnées sont réduites au minimum vital.",
                en: "Yes. Poof encrypts every transfer in AES-256 client-side. Servers never see the content — even metadata is stripped to the minimum required."
            )
        )
    ]

    @State private var expandedId: UUID?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Self.items) { item in
                itemView(item)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Item

    private func itemView(_ item: Item) -> some View {
        let isOpen = expandedId == item.id
        return Button {
            PoofHaptics.soft()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                expandedId = isOpen ? nil : item.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(item.question.localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }

                if isOpen {
                    Text(item.answer.localized)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isOpen ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
