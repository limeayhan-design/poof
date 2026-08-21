#if os(iOS)
    import AppIntents
    import Foundation
    import UIKit

    // Regroupe les App Intents Poof — accessibles depuis :
    //  - Action Button iPhone 15 Pro+ (Réglages → Bouton d'action → Raccourci)
    //  - Siri (« Coller Poof », « Envoyer clipboard Poof »)
    //  - Spotlight search
    //  - App Raccourcis
    //  - Control Center widget (via ControlWidgetButton)
    //  - Widget Home Screen (via Button(intent:))

    // MARK: - Shared store (App Group UserDefaults)

    /// Miroir minimaliste de `PoofClipboardStore` accessible par le widget
    /// target (qui n'inclut pas Combine/@MainActor du full store). Même
    /// App Group + mêmes clés → single source of truth.
    enum PoofSharedIntentStore {
        static let appGroupId = "group.com.poofapp.shared"

        private static let lastClipboardText = "poof.lastClipboardText"
        private static let lastClipboardSender = "poof.lastClipboardSender"
        private static let lastPeerDeviceId = "poof.lastPeerDeviceId"
        private static let lastPeerName = "poof.lastPeerName"
        private static let selfDeviceId = "poof.selfDeviceId"
        private static let selfDeviceName = "poof.selfDeviceName"
        private static let signalingURL = "poof.signalingURL"

        static var defaults: UserDefaults {
            UserDefaults(suiteName: appGroupId) ?? .standard
        }

        static var lastClipboard: (text: String, sender: String)? {
            let d = defaults
            guard let text = d.string(forKey: lastClipboardText), !text.isEmpty else { return nil }
            return (text, d.string(forKey: lastClipboardSender) ?? "Device")
        }

        static var lastPeer: (deviceId: String, name: String)? {
            let d = defaults
            guard let id = d.string(forKey: lastPeerDeviceId), !id.isEmpty else { return nil }
            return (id, d.string(forKey: lastPeerName) ?? "Device")
        }

        static func setLastPeer(deviceId: String, name: String) {
            let d = defaults
            d.set(deviceId, forKey: lastPeerDeviceId)
            d.set(name, forKey: lastPeerName)
        }

        static var selfIdentity: (deviceId: String, name: String) {
            let d = defaults
            return (
                d.string(forKey: selfDeviceId) ?? "",
                d.string(forKey: selfDeviceName) ?? "iPhone"
            )
        }

        static func setSelfIdentity(deviceId: String, name: String) {
            let d = defaults
            d.set(deviceId, forKey: selfDeviceId)
            d.set(name, forKey: selfDeviceName)
        }

        static var relayBaseURL: URL {
            let d = defaults
            let str = d.string(forKey: signalingURL) ?? "https://poof-fgb8.onrender.com"
            return URL(string: str) ?? URL(string: "https://poof-fgb8.onrender.com")!
        }
    }

    // MARK: - Intent 1 : coller le dernier clipboard reçu

    /// Écrit le dernier clipboard reçu dans `UIPasteboard`. `openAppWhenRun`
    /// = false → tourne en foreground context implicite (via Action Button /
    /// widget / Siri), pasteboard write autorisé.
    struct PastePoofClipboardIntent: AppIntent {
        static var title: LocalizedStringResource = "Paste from Poof"
        static var description = IntentDescription(
            "Pastes the last text received from a linked Poof device."
        )
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            guard let entry = PoofSharedIntentStore.lastClipboard else {
                return .result(dialog: "No clipboard received from Poof yet.")
            }
            await MainActor.run {
                UIPasteboard.general.string = entry.text
                UIPasteboard.general.setValue(entry.text, forPasteboardType: "public.utf8-plain-text")
            }
            let preview = entry.text.count > 40 ? String(entry.text.prefix(40)) + "…" : entry.text
            return .result(dialog: "Pasted from \(entry.sender): \(preview)")
        }
    }

    // MARK: - Intent 2 : envoyer le clipboard courant à un peer

    /// Envoie le contenu de `UIPasteboard.general.string` au dernier peer
    /// paired Poof via POST /relay/clipboard. Marche depuis Action Button —
    /// l'user tap le bouton, le texte copié est instantanément envoyé.
    struct SendClipboardWithPoofIntent: AppIntent {
        static var title: LocalizedStringResource = "Send clipboard with Poof"
        static var description = IntentDescription(
            "Sends the current clipboard content to the last linked Poof device."
        )
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            let text = await MainActor.run { UIPasteboard.general.string }
            guard let text, !text.isEmpty else {
                return .result(dialog: "No text in the clipboard.")
            }
            guard let peer = PoofSharedIntentStore.lastPeer else {
                return .result(dialog: "No linked Poof device. Open the app to pair a device.")
            }
            let identity = PoofSharedIntentStore.selfIdentity
            do {
                try await postClipboard(
                    text: text,
                    targetDeviceId: peer.deviceId,
                    senderDeviceId: identity.deviceId,
                    senderName: identity.name
                )
                let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
                return .result(dialog: "Sent to \(peer.name): \(preview)")
            } catch {
                return .result(dialog: "Send failed: \(error.localizedDescription)")
            }
        }

        private func postClipboard(
            text: String, targetDeviceId: String,
            senderDeviceId: String, senderName: String
        ) async throws {
            let url = PoofSharedIntentStore.relayBaseURL.appendingPathComponent("relay/clipboard")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "targetDeviceId": targetDeviceId,
                "senderDeviceId": senderDeviceId,
                "senderName": senderName,
                "text": text
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw NSError(
                    domain: "PoofIntent", code: status,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"]
                )
            }
        }
    }

    // MARK: - App Shortcuts Provider

    /// Expose les intents pour Action Button, Siri, Spotlight, Raccourcis.
    /// Les phrases sont les tournures que Siri reconnaît (FR + EN mixed).
    struct PoofAppShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: PastePoofClipboardIntent(),
                phrases: [
                    "Paste from \(.applicationName)",
                    "\(.applicationName) paste",
                    "Show last \(.applicationName) clipboard"
                ],
                shortTitle: "Paste Poof",
                systemImageName: "doc.on.clipboard.fill"
            )
            AppShortcut(
                intent: SendClipboardWithPoofIntent(),
                phrases: [
                    "Send clipboard with \(.applicationName)",
                    "Share my clipboard with \(.applicationName)",
                    "\(.applicationName) send my clipboard"
                ],
                shortTitle: "Send Poof clipboard",
                systemImageName: "paperplane.fill"
            )
        }
    }
#endif
