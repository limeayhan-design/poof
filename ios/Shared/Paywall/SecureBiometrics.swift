import Foundation
import LocalAuthentication

/// Wrapper léger autour de LAContext — utilisé par le gate biometrics
/// d'un fichier Secure (Face ID / Touch ID requis avant preview).
enum SecureBiometrics {
    /// Pré-warm : appelé dès qu'on SAIT que biométrie va être demandée
    /// (typiquement au sheet.onAppear). Réduit la latence du prompt de
    /// ~200-500ms car iOS charge les modèles Face ID + init caméra à l'avance.
    static func prewarm() {
        Task.detached(priority: .userInitiated) {
            let context = LAContext()
            var error: NSError?
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        }
    }

    /// Déclenche l'authentification biométrique de la plateforme (Face ID
    /// sur iPhone récent, Touch ID sur Mac / iPad avec bouton).
    /// - Returns: `true` si l'utilisateur est authentifié, `false` sinon
    ///   (annulé, échec, non disponible sur l'appareil). Le prompt reason
    ///   est localisé côté OS (message système standard).
    static func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        // Skip le bouton "Entrez le mot de passe" du prompt — un tap dessus
        // ralentit le flow (ouvre un pinpad système). L'utilisateur peut
        // toujours annuler et retomber sur notre passcode custom si besoin.
        context.localizedFallbackTitle = ""
        // Cache l'auth 10s : si l'utilisateur re-ouvre un autre fichier
        // Secure juste après, on skip le Face ID sans re-scan.
        context.touchIDAuthenticationAllowableReuseDuration = 10

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
