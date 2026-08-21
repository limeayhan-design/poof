import SwiftUI

// Business tier: on-device workspace store.
// Name, logo char, accent color, per-peer role. All persisted in UserDefaults.

enum BusinessWorkspace {
    static let keyName = "poof.workspace.name"
    static let keyLogo = "poof.workspace.logo"
    static let keyColor = "poof.workspace.color"
    static let keyRoles = "poof.workspace.roles"

    static let colorPresets: [String] = [
        "#5B8BFF", "#8B7EFF", "#3FBF7F", "#FF7A9C", "#FFBF3C", "#FF5C52"
    ]

    static let defaultColor = "#5B8BFF"
    static let defaultLogo = "P"

    static let roles: [String] = ["Admin", "Member", "Guest"]

    static var name: String {
        get { UserDefaults.standard.string(forKey: keyName) ?? "" }
        set {
            let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                UserDefaults.standard.removeObject(forKey: keyName)
            } else {
                UserDefaults.standard.set(t, forKey: keyName)
            }
        }
    }

    static var logo: String {
        get { UserDefaults.standard.string(forKey: keyLogo) ?? defaultLogo }
        set {
            let t = String(newValue.prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = t.isEmpty ? defaultLogo : t
            UserDefaults.standard.set(v, forKey: keyLogo)
        }
    }

    static var color: String {
        get { UserDefaults.standard.string(forKey: keyColor) ?? defaultColor }
        set { UserDefaults.standard.set(newValue, forKey: keyColor) }
    }

    static var accent: Color {
        Color(hex: color)
    }

    static func role(for peerId: String) -> String {
        rolesDict[peerId] ?? "Member"
    }

    static func setRole(_ role: String, for peerId: String) {
        var dict = rolesDict
        dict[peerId] = role
        setRolesDict(dict)
    }

    static var rolesDict: [String: String] {
        guard let data = UserDefaults.standard.data(forKey: keyRoles),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func setRolesDict(_ dict: [String: String]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: keyRoles)
        }
    }
}

// init(hex:) is now defined in PoofColors.swift (single source of truth).
