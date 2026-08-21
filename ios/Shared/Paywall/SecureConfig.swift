import Foundation

/// Configuration d'un envoi Secure — options qui s'appliquent au fichier
/// juste avant le transfert. Un `nil` = mode Secure OFF, une instance = ON
/// avec ces paramètres.
struct SecureConfig: Equatable, Codable {
    var passcode: PasscodePolicy
    var expiry: ExpiryPolicy
    var oneTimeView: Bool
    var watermark: WatermarkPolicy
    var biometrics: Bool

    /// Preset appliqué au 1er tap sur le chip Secure — l'utilisateur peut
    /// tout affiner via long-press + sheet config, mais ces réglages sont
    /// "cliquez et envoyez" par défaut : sécurité correcte sans friction.
    static let defaults = SecureConfig(
        passcode: .off,
        expiry: .oneDay,
        oneTimeView: false,
        watermark: .off,
        biometrics: false
    )
}

// MARK: - Passcode

enum PasscodePolicy: Equatable, Codable {
    case off
    /// Code 4-6 chiffres. La string est stockée hashée côté serveur ; ici
    /// on la garde en clair uniquement dans la session courante.
    case digits(String)

    var isEnabled: Bool {
        if case .off = self {
            return false
        }
        return true
    }
}

// MARK: - Expiry

enum ExpiryPolicy: Equatable, Codable {
    case oneHour, oneDay, sevenDays, thirtyDays, never
    /// Date d'expiration absolue choisie via DatePicker par l'utilisateur.
    case customDate(Date)

    /// Presets courts pour le picker capsule (custom en dehors).
    /// Presets courts proposés dans le picker capsule. `.never` a été retiré
    /// volontairement : un envoi Secure doit toujours avoir une durée de vie
    /// finie pour que la promesse « auto-destruct » soit tenable. L'utilisateur
    /// qui veut « pas d'expiration » n'utilise simplement pas le chip Secure.
    static let presets: [ExpiryPolicy] = [.oneHour, .oneDay, .sevenDays, .thirtyDays]

    var label: L10n {
        switch self {
        case .oneHour: L10n(fr: "1 heure", en: "1 hour")
        case .oneDay: L10n(fr: "24 heures", en: "24 hours")
        case .sevenDays: L10n(fr: "7 jours", en: "7 days")
        case .thirtyDays: L10n(fr: "30 jours", en: "30 days")
        case .never: L10n(fr: "Jamais", en: "Never")
        case .customDate: L10n(fr: "Date custom", en: "Custom date")
        }
    }

    /// Nil = jamais expire. Sinon durée en secondes depuis l'envoi. Pour
    /// `customDate`, recalcul à chaque call depuis la date absolue (peut
    /// être négatif si déjà passée — le sweeper purge alors immédiatement).
    var duration: TimeInterval? {
        switch self {
        case .oneHour: 60 * 60
        case .oneDay: 60 * 60 * 24
        case .sevenDays: 60 * 60 * 24 * 7
        case .thirtyDays: 60 * 60 * 24 * 30
        case .never: nil
        case let .customDate(date): max(0, date.timeIntervalSinceNow)
        }
    }

    var isCustom: Bool {
        if case .customDate = self {
            return true
        }
        return false
    }
}

// MARK: - Watermark

enum WatermarkPolicy: Equatable, Codable {
    case off
    /// Nom du destinataire injecté automatiquement en filigrane.
    case recipientName
    /// Texte custom fourni par l'expéditeur.
    case custom(String)

    var isEnabled: Bool {
        if case .off = self {
            return false
        }
        return true
    }
}
