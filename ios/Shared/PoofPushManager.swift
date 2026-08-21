import Combine
import Foundation
import UserNotifications

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Manager APNS singleton — registre l'app pour recevoir des remote push,
/// expose le device token, et le persiste pour que la couche signaling
/// puisse l'envoyer au serveur au bon moment.
///
/// **Pourquoi APNS ?** Sans push, iOS suspend l'app en ~30s après background.
/// WebRTC coupe et aucun event Track ne peut arriver. Les push permettent
/// au serveur de wake up l'app (silent) OU d'afficher directement une notif
/// utilisateur ("File opened by X") même app killed.
///
/// **Flow :**
/// 1. Launch → `register()` → OS renvoie deviceToken via AppDelegate
/// 2. Token stocké dans `deviceToken` + `onTokenReceived` fire
/// 3. `PoofSession` register le token auprès du serveur signaling
/// 4. Receiver ouvre fichier → serveur envoie push APNS au sender
/// 5. iOS wake up l'app + affiche la notif
@MainActor
final class PoofPushManager: ObservableObject {
    static let shared = PoofPushManager()

    @Published private(set) var deviceToken: String?
    @Published private(set) var lastError: String?

    /// Fire quand un token frais arrive. Utilisé par `PoofSession` pour
    /// register auprès du serveur signaling. Idempotent : rappelé à chaque
    /// re-register (iOS peut invalidate + réémettre).
    var onTokenReceived: ((String) -> Void)?

    private init() {}

    /// Demande l'auth notif + register pour remote push. À call au launch
    /// après l'auth notif locale (PoofTrackNotifier), les deux flows sont
    /// compatibles côte à côte.
    func register() {
        // Category + delegate déjà installés dans `PoofAppDelegate.init()`
        // (voir installNotificationHandlers plus bas). On garde cette méthode
        // pour l'authorization + registerForRemoteNotifications qui doivent
        // rester triggered après le launch pour respecter le prompt user.
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("[Poof] APNS auth error: \(error)")
                return
            }
            print("[Poof] APNS auth granted = \(granted)")
            guard granted else { return }
            DispatchQueue.main.async {
                #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                #elseif canImport(AppKit)
                    NSApplication.shared.registerForRemoteNotifications()
                #endif
            }
        }
    }

    /// Appelé par l'AppDelegate quand APNS renvoie un device token.
    /// Format : Data → hex string, à envoyer tel quel au serveur.
    func handleTokenData(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
            print("[Poof] APNS device token received (\(hex.count) chars)")
        #endif
        deviceToken = hex
        onTokenReceived?(hex)
    }

    func handleRegistrationError(_ error: Error) {
        #if DEBUG
            print("[Poof] APNS registration failed: \(error)")
        #endif
        lastError = error.localizedDescription
    }
}

// MARK: - Notification delegate (handle "📋 Coller" action)

/// Handler pour l'action « Coller » du push clipboard. Le tap sur le bouton
/// exécute ce handler en background, sans forcer l'app en foreground —
/// l'user peut coller le texte n'importe où sans quitter son contexte.
final class PoofNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PoofNotificationDelegate()

    /// Notifs affichées quand l'app EST en foreground — sans ça iOS les
    /// masque par défaut. On garde le bouton "Paste" accessible même
    /// quand l'user est déjà dans Poof.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handler central quand l'user interagit avec une notif. Deux cas :
    ///  - tap sur le bouton « 📋 Coller » → on écrit le texte dans le
    ///    pasteboard, l'app reste dans son état (background/fermée).
    ///  - tap sur le corps de la notif → iOS ouvre l'app par défaut, on
    ///    en profite pour aussi coller (best-effort UX).
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let text = userInfo["text"] as? String
        guard response.actionIdentifier == "COPY_CLIPBOARD"
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let text, !text.isEmpty
        else {
            completionHandler()
            return
        }
        // iOS 14+ throttle l'écriture pasteboard depuis un handler background.
        // On dispatch sur main, écrit, puis on retient le completionHandler
        // ~0.6s pour laisser iOS committer l'écriture avant de killer le
        // process. Sans ce delay, l'user tape « Coller » mais rien n'arrive
        // dans le pasteboard (le process meurt trop vite).
        DispatchQueue.main.async {
            // Persiste dans le store partagé — le menu bar Mac / Control
            // Center widget iOS pourront re-coller au clic, contournant
            // ainsi la restriction iOS 14+ pasteboard bg (leur context
            // est foreground implicite).
            let senderName = (userInfo["senderName"] as? String) ?? "Device"
            Task { @MainActor in
                PoofClipboardStore.shared.record(text: text, senderName: senderName)
            }
            #if canImport(UIKit)
                // Triple-write via 3 APIs différentes — best-effort, iOS 14+
                // throttle depuis un handler bg. Le fallback fiable = tap le
                // widget Control Center (voir PoofClipboardStore).
                UIPasteboard.general.string = text
                UIPasteboard.general.setValue(text, forPasteboardType: "public.utf8-plain-text")
                UIPasteboard.general.setItems(
                    [["public.utf8-plain-text": text, "public.plain-text": text]],
                    options: [.localOnly: true]
                )
            #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif

            // Feedback visuel : notif locale de confirmation. Si l'user voit
            // "✓ Collé" apparaître → le handler est bien atteint. Si le
            // pasteboard reste vide malgré ça → limitation iOS bg pasteboard
            // (auquel cas basculer sur .foreground option).
            let content = UNMutableNotificationContent()
            content.title = "✓ Copied to clipboard"
            content.body = text.count > 60 ? String(text.prefix(60)) + "…" : text
            content.sound = nil
            let request = UNNotificationRequest(
                identifier: "clipboard-copied-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                completionHandler()
            }
        }
    }
}

// MARK: - AppDelegate adapters (iOS + Mac)

/// Installe le delegate + la category `CLIPBOARD_INBOUND` le PLUS TÔT
/// possible dans le cycle de vie de l'app. Si l'app est tuée quand la notif
/// arrive puis relaunchée par le tap user, iOS appelle `didReceive` très tôt
/// — avant `PoofPushManager.register()` — donc le delegate doit être set
/// dès l'init du AppDelegate sinon le handler « Coller » ne trigge pas.
private func installNotificationHandlers() {
    let copyAction = UNNotificationAction(
        identifier: "COPY_CLIPBOARD",
        title: "📋 Coller",
        options: []
    )
    let clipboardCategory = UNNotificationCategory(
        identifier: "CLIPBOARD_INBOUND",
        actions: [copyAction],
        intentIdentifiers: [],
        options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([clipboardCategory])
    UNUserNotificationCenter.current().delegate = PoofNotificationDelegate.shared
}

#if canImport(UIKit)
    final class PoofAppDelegate: NSObject, UIApplicationDelegate {
        override init() {
            super.init()
            installNotificationHandlers()
        }

        func application(
            _: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            Task { @MainActor in
                PoofPushManager.shared.handleTokenData(deviceToken)
            }
        }

        func application(
            _: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: Error
        ) {
            Task { @MainActor in
                PoofPushManager.shared.handleRegistrationError(error)
            }
        }
    }
#elseif canImport(AppKit)
    final class PoofAppDelegate: NSObject, NSApplicationDelegate {
        override init() {
            super.init()
            installNotificationHandlers()
        }

        func application(
            _: NSApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            Task { @MainActor in
                PoofPushManager.shared.handleTokenData(deviceToken)
            }
        }

        func application(
            _: NSApplication,
            didFailToRegisterForRemoteNotificationsWithError error: Error
        ) {
            Task { @MainActor in
                PoofPushManager.shared.handleRegistrationError(error)
            }
        }
    }
#endif
