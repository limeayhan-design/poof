import Foundation
import UIKit

// Persistent local identity for this Poof install (mirror of pc/src/device-identity.js).

enum PoofDeviceIdentity {
    private static let idKey = "poof.deviceId"
    private static let nameKey = "poof.deviceName"

    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: idKey) { return existing }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: idKey)
        return fresh
    }

    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? suggestedName }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: nameKey) }
            else { UserDefaults.standard.set(trimmed, forKey: nameKey) }
        }
    }

    static var hasCustomName: Bool {
        UserDefaults.standard.string(forKey: nameKey) != nil
    }

    static var suggestedName: String {
        let model = UIDevice.current.model
        let name = UIDevice.current.name
        if !name.isEmpty && name != model { return name }
        return model  // "iPhone" / "iPad"
    }

    static let platform: String = {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "ios-pad"
        default:   return "ios"
        }
    }()
}
