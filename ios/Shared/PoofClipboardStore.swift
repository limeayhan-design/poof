import Combine
import Foundation

/// Persiste le dernier clipboard reçu via relay pour être accessible depuis
/// des surfaces alternatives (menu bar macOS, Control Center widget iOS,
/// Home Screen widget interactive). Ces surfaces peuvent écrire dans le
/// pasteboard système SANS ouvrir l'app — contrairement aux handlers de
/// notification action qui sont bloqués en background par iOS 14+.
///
/// Stockage via UserDefaults App Group (`group.com.poofapp.shared`) pour
/// que le widget iOS (target extension séparé) partage la même donnée.
/// Sur Mac, comme le menu bar tourne dans le même process, UserDefaults
/// suite est utilisé aussi par cohérence (single source of truth).
@MainActor
final class PoofClipboardStore: ObservableObject {
    static let shared = PoofClipboardStore()

    private static let appGroupId = "group.com.poofapp.shared"
    private static let textKey = "poof.lastClipboardText"
    private static let senderKey = "poof.lastClipboardSender"
    private static let timestampKey = "poof.lastClipboardTs"

    struct Entry: Equatable {
        let text: String
        let senderName: String
        let receivedAt: Date

        var preview: String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 60 {
                return String(trimmed.prefix(60)) + "…"
            }
            return trimmed
        }
    }

    @Published private(set) var latest: Entry?

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupId) ?? .standard
    }

    private init() {
        reload()
    }

    /// Persiste un nouveau clipboard reçu. Écrase le précédent — on ne garde
    /// que le dernier (comme un pasteboard, pas un historique).
    func record(text: String, senderName: String) {
        let now = Date()
        let d = defaults
        d.set(text, forKey: Self.textKey)
        d.set(senderName, forKey: Self.senderKey)
        d.set(now.timeIntervalSince1970, forKey: Self.timestampKey)
        latest = Entry(text: text, senderName: senderName, receivedAt: now)
    }

    /// Re-lit depuis UserDefaults — utile pour synchroniser le widget iOS
    /// après un update poussé par le container app.
    func reload() {
        let d = defaults
        guard let text = d.string(forKey: Self.textKey), !text.isEmpty else {
            latest = nil
            return
        }
        let sender = d.string(forKey: Self.senderKey) ?? "Device"
        let ts = d.double(forKey: Self.timestampKey)
        latest = Entry(text: text, senderName: sender, receivedAt: Date(timeIntervalSince1970: ts))
    }

    /// Écrit le dernier clipboard reçu dans le pasteboard système. Appelé
    /// par le menu bar Mac ou le widget iOS quand l'user tap « Coller ».
    /// Retourne le texte collé pour permettre au caller d'afficher un
    /// feedback (haptique, toast, badge).
    @discardableResult
    func pasteLatestToSystem() -> String? {
        guard let entry = latest else { return nil }
        PoofPlatform.setClipboardString(entry.text)
        return entry.text
    }
}
