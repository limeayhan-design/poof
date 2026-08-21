import Combine
import SwiftUI

/// Source de vérité centrale pour présenter la paywall depuis n'importe où
/// dans l'app — bannière Send view, gate technique (fichier trop gros,
/// batch trop grand), entry point d'une feature Premium, etc.
///
/// Usage :
/// ```
/// // Bannière Premium — pas de kind, ouvre le hero orbite.
/// PoofPremiumGate.shared.present()
///
/// // Gate contextuel — ouvre directement sur la section Boost.
/// PoofPremiumGate.shared.present(scrollTo: .boost)
/// ```
///
/// La paywall est présentée via `.premiumPaywallSheet()` appliqué sur la root
/// view (iOS + macOS) — un seul point de présentation, pas de duplication.
@MainActor
final class PoofPremiumGate: ObservableObject {
    static let shared = PoofPremiumGate()

    @Published var isPresented: Bool = false
    @Published var initialScrollTarget: PremiumFeatureKind?

    private init() {}

    /// Ouvre l'écran Premium. Pendant la beta pré-launch, on affiche
    /// `PremiumComingSoonView` (annonce + reward 1 mois). Le paywall payant
    /// (`PoofPaywallView`) reste dans le repo pour être réactivé le jour du
    /// launch — il suffira de remettre le routing ici.
    /// Note beta : on ne skip PLUS quand `isPremium == true` (ancien guard),
    /// sinon les Mac avec `debugPremium` activé ne pouvaient plus ouvrir
    /// l'écran Coming soon. À réactiver au launch officiel.
    func present(scrollTo kind: PremiumFeatureKind? = nil) {
        PoofHaptics.soft()
        initialScrollTarget = kind
        isPresented = true
    }
}

// MARK: - Root view modifier

extension View {
    /// À appliquer sur la root view de chaque plateforme (iOS + macOS).
    /// Un seul modifier suffit pour toute l'app — le gate est un singleton.
    func premiumPaywallSheet() -> some View {
        modifier(PremiumPaywallSheetModifier())
    }
}

private struct PremiumPaywallSheetModifier: ViewModifier {
    @StateObject private var gate = PoofPremiumGate.shared

    func body(content: Content) -> some View {
        // Pré-launch : on affiche l'écran « Coming soon » + reward beta au
        // lieu du paywall payant. À la sortie officielle du Premium, remettre
        // `PoofPaywallView(initialScrollTarget: gate.initialScrollTarget)`.
        content.sheet(isPresented: $gate.isPresented) {
            PremiumComingSoonView()
        }
    }
}
