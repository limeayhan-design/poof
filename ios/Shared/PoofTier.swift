import SwiftUI

// Subscription tiers. Persisted in UserDefaults via @AppStorage("poof.tier").
// Theme accent + background glow adapt automatically to the selected tier.

enum PoofTier: String, CaseIterable, Identifiable {
    case free, premium, family, devium, business

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .free: "Standard"
        case .premium: "Premium"
        case .family: "Family"
        case .devium: "Devium"
        case .business: "Business"
        }
    }

    var priceLabel: String {
        switch self {
        case .free: "Free forever"
        case .premium: "€4.99 / month"
        case .family: "€6.99 / month"
        case .devium: "€9.99 / month"
        case .business: "€19.99 / user"
        }
    }

    var tagline: String {
        switch self {
        case .free: "AirDrop for everyone."
        case .premium: "Your files. All devices. Everywhere."
        case .family: "Share with the people you love."
        case .devium: "For developers who ship."
        case .business: "Poof for teams."
        }
    }

    /// Accent color drives buttons, dots, active borders, CTA highlights.
    var accent: Color {
        switch self {
        case .free: Color(red: 0.247, green: 0.749, blue: 0.498) // #3FBF7F
        case .premium: Color(red: 0.357, green: 0.545, blue: 1.0) // #5B8BFF
        case .family: Color(red: 1.0, green: 0.478, blue: 0.612) // #FF7A9C
        case .devium: Color(red: 0.545, green: 0.494, blue: 1.0) // #8B7EFF
        case .business: Color(red: 0.561, green: 0.639, blue: 0.710) // #8FA3B5
        }
    }

    /// Secondary accent for background glows (slightly shifted hue).
    var glow: Color {
        switch self {
        case .free: Color(red: 0.451, green: 0.867, blue: 0.671) // lighter green
        case .premium: Color(red: 0.486, green: 0.647, blue: 1.0) // lighter blue
        case .family: Color(red: 1.0, green: 0.647, blue: 0.749) // lighter coral
        case .devium: Color(red: 0.647, green: 0.580, blue: 1.0) // lighter violet
        case .business: Color(red: 0.678, green: 0.741, blue: 0.804) // lighter steel
        }
    }
}

/// Storage helper — read/write @AppStorage("poof.tier") from anywhere.
extension PoofTier {
    static let storageKey = "poof.tier"

    static var current: PoofTier {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? PoofTier.free.rawValue
        return PoofTier(rawValue: raw) ?? .free
    }

    /// Tiers exposés dans le paywall public. Family / Devium / Business
    /// sont cachés pour l'instant (features gardées en code, réactivables).
    static let visibleTiers: [PoofTier] = [.free, .premium]
}
