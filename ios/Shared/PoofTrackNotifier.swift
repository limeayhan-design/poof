import Foundation
import UserNotifications

/// Vraies notifications système côté sender à chaque event Track reçu —
/// visibles même si l'app est en background ou fermée, comme Snapchat.
///
/// Le toast in-app (`session.toast`) ne s'affiche que si l'app est au 1er
/// plan. Cette classe complète : `UNNotificationRequest` livrée immédiatement
/// par le système, s'affiche en banner + son même app fermée.
///
/// Aucune infra serveur : l'event vient déjà par le canal WebRTC / MC entre
/// les deux devices. On se contente de le convertir en notif locale.
@MainActor
enum PoofTrackNotifier {
    private static var authRequested = false

    /// Appelé au launch pour trigger la permission sheet native AVANT qu'un
    /// event Track arrive. Sinon la 1re alerte est silencieusement drop
    /// pendant que la sheet native est encore pending.
    static func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                poofLog("[Poof] Track notif auth error: \(error)")
            }
            poofLog("[Poof] Track notif auth granted = \(granted)")
        }
    }

    /// Livre une notif « Opened by [device] » au sender. Idempotent sur l'auth.
    static func fireOpened(sender deviceLabel: String, fileName: String) {
        requestAuthIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "File opened"
        content.body = "\(deviceLabel) opened \(fileName)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "poof.track.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        poofLog("[Poof] Firing Track notif — sender=\(deviceLabel), file=\(fileName)")
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                poofLog("[Poof] Track notif deliver error: \(error)")
            } else {
                poofLog("[Poof] Track notif delivered OK")
            }
        }
    }
}
