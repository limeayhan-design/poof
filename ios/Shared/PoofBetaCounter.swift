import Combine
import Foundation
import SwiftUI

/// Compteur des envois réussis pendant la beta pré-Premium. À la sortie
/// officielle du Premium, tout utilisateur ayant atteint le seuil
/// (`targetCount`) débloque 1 mois Premium offert — mécanique d'acquisition
/// et de récompense pour les early adopters.
///
/// Le comptage est local (UserDefaults). Un envoi = un fichier délivré avec
/// succès sur un canal (relay HTTPS, WebRTC direct, ou MultipeerConnectivity
/// hors-ligne). Un broadcast à N destinataires reste un seul point pour
/// éviter de gonfler artificiellement le score.
@MainActor
final class PoofBetaCounter: ObservableObject {
    static let shared = PoofBetaCounter()

    /// Seuil d'envois pour débloquer le mois Premium offert au lancement.
    /// Choisi assez haut pour filtrer les curieux qui installent puis
    /// n'utilisent pas, assez bas pour rester atteignable en quelques
    /// jours d'usage normal.
    static let targetCount: Int = 20

    @AppStorage("poof.beta.sendCount") private var storedCount: Int = 0
    @Published private(set) var sendCount: Int = 0

    private init() {
        sendCount = storedCount
    }

    /// À appeler à chaque envoi de fichier confirmé délivré. Idempotent :
    /// une fois `targetCount` atteint, on continue à incrémenter (utile
    /// pour un futur écran de stats), mais l'UI capse l'affichage à
    /// `targetCount` pour ne pas déborder de la barre.
    func recordSuccessfulSend() {
        storedCount += 1
        sendCount = storedCount
    }

    var progress: Double {
        min(1.0, Double(sendCount) / Double(Self.targetCount))
    }

    var isUnlocked: Bool {
        sendCount >= Self.targetCount
    }

    var remaining: Int {
        max(0, Self.targetCount - sendCount)
    }

    #if DEBUG
        /// Reset uniquement en DEBUG pour retester la mécanique d'onboarding
        /// sans réinstaller l'app. Absent des builds Release.
        func debugReset() {
            storedCount = 0
            sendCount = 0
        }
    #endif
}
