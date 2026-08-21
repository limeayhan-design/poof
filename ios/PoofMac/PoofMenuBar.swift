import AppKit
import Combine
import SwiftUI

/// NSStatusItem persistant dans la menu bar macOS. Bouton principal :
/// « 📋 Coller dernier clipboard » — un click écrit dans NSPasteboard sans
/// ouvrir l'app. C'est le contournement propre de la restriction iOS-like
/// pasteboard bg : le menu bar item est du foreground context implicite
/// (process app tourne, user click = user-initiated).
@MainActor
final class PoofMenuBarController {
    static let shared = PoofMenuBarController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// À appeler au launch de l'app Mac (dans PoofMacApp.task). Idempotent —
    /// si déjà installé, no-op.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Poof")?
                .withSymbolConfiguration(cfg)
            button.image?.isTemplate = true
            button.toolTip = "Poof — clipboard received"
        }
        item.menu = buildMenu()
        statusItem = item

        // Reconstruire le menu quand un nouveau clipboard arrive — le preview
        // dans la ligne « Coller » doit refléter le contenu à jour.
        PoofClipboardStore.shared.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusItem?.menu = self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let entry = PoofClipboardStore.shared.latest {
            // Item principal — cliquable, colle direct dans le pasteboard.
            let pasteItem = NSMenuItem(
                title: "📋 Paste: \(entry.preview)",
                action: #selector(pasteClicked),
                keyEquivalent: "v"
            )
            pasteItem.keyEquivalentModifierMask = [.command, .shift]
            pasteItem.target = self
            menu.addItem(pasteItem)

            let senderItem = NSMenuItem(
                title: "From \(entry.senderName) · \(Self.timeAgo(entry.receivedAt))",
                action: nil, keyEquivalent: ""
            )
            senderItem.isEnabled = false
            menu.addItem(senderItem)
        } else {
            let emptyItem = NSMenuItem(
                title: "No clipboard received",
                action: nil, keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "Open Poof",
            action: #selector(openAppClicked),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(
            title: "Quit Poof",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func pasteClicked() {
        guard let text = PoofClipboardStore.shared.pasteLatestToSystem() else { return }
        // Feedback discret : notification banner « ✓ Collé » (Mac autorise
        // les notifs même menu bar).
        let content = UNMutableNotificationContent()
        content.title = "✓ Copied to clipboard"
        content.body = text.count > 60 ? String(text.prefix(60)) + "…" : text
        let request = UNNotificationRequest(
            identifier: "clipboard-pasted-\(UUID().uuidString)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    @objc private func openAppClicked() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3600 {
            return "\(seconds / 60) min ago"
        }
        if seconds < 86400 {
            return "\(seconds / 3600) h ago"
        }
        return "\(seconds / 86400) d ago"
    }
}

// Import UserNotifications pour la notif de confirmation "✓ Collé".
import UserNotifications
