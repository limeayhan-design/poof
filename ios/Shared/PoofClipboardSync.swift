import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// Local clipboard bridge — mirrors pc/src/clipboard-sync.js.
// iOS  : UIPasteboard.changedNotification (foreground only).
// macOS: NSPasteboard n'a pas de notification native → polling léger sur
//        changeCount (0.6 s), suffisant pour un clipboard humain.

final class PoofClipboardSync {
    struct Item: Equatable {
        let text: String
        let date: Date
        let origin: Origin
        enum Origin { case local, remote }
    }

    private(set) var history: [Item] = []
    var onIncoming: ((Item) -> Void)?

    /// When false, silent clipboard changes are NOT auto-broadcast.
    /// A user-triggered pushCurrent() still works either way.
    var autoPushEnabled: Bool = false

    private weak var manager: PoofWebRTCManager?
    private var lastLocalFingerprint: String?
    private var lastRemoteFingerprint: String?

    #if canImport(UIKit)
        private var observer: NSObjectProtocol?
    #elseif canImport(AppKit)
        private var pollTimer: Timer?
        private var lastChangeCount: Int = NSPasteboard.general.changeCount
    #endif

    init(manager: PoofWebRTCManager) {
        self.manager = manager
        #if canImport(UIKit)
            observer = NotificationCenter.default.addObserver(
                forName: UIPasteboard.changedNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.handleLocalChange(force: false) }
        #elseif canImport(AppKit)
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                guard let self else { return }
                let current = NSPasteboard.general.changeCount
                guard current != lastChangeCount else { return }
                lastChangeCount = current
                handleLocalChange(force: false)
            }
        #endif
    }

    deinit {
        #if canImport(UIKit)
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        #elseif canImport(AppKit)
            pollTimer?.invalidate()
        #endif
    }

    func pushCurrent() {
        handleLocalChange(force: true)
    }

    func handle(_ env: PoofEnvelope) {
        switch env.type {
        case .clipboard: receive(env)
        case .clipboardAck: break
        default: break
        }
    }

    private func handleLocalChange(force: Bool) {
        guard let text = PoofPlatform.clipboardString, !text.isEmpty else { return }
        let fp = fingerprint(text)
        if fp == lastRemoteFingerprint {
            return
        }
        if !force, fp == lastLocalFingerprint {
            return
        }
        if !force, !autoPushEnabled {
            return
        }
        lastLocalFingerprint = fp

        remember(Item(text: text, date: Date(), origin: .local))

        let env = PoofEnvelope(
            type: .clipboard,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: force,
            payload: ["text": text, "fp": fp]
        )
        // Fiabilité — capture le retour de sendEnvelope. Si le canal control
        // est fermé (peer offline, handshake en cours), on met en file d'attente
        // pour retry au prochain flush. Sinon on perd le clipboard sans
        // aucun feedback.
        let sent = manager?.sendEnvelope(env) ?? false
        if !sent {
            pendingQueue.append(env)
            // Cap à 20 entrées — sinon un peer offline longtemps mangerait
            // toute la RAM.
            if pendingQueue.count > 20 {
                pendingQueue.removeFirst(pendingQueue.count - 20)
            }
        }
    }

    /// À appeler par PoofSession quand le control channel repasse `.open`.
    /// Vide la file d'attente clipboard qui n'a pas pu partir en direct.
    func flushPending() {
        guard let mgr = manager, !pendingQueue.isEmpty else { return }
        let queue = pendingQueue
        pendingQueue.removeAll()
        for env in queue {
            _ = mgr.sendEnvelope(env)
        }
    }

    private var pendingQueue: [PoofEnvelope] = []

    private func receive(_ env: PoofEnvelope) {
        guard let text = env.payload["text"] as? String else { return }
        let fp = (env.payload["fp"] as? String) ?? fingerprint(text)
        lastRemoteFingerprint = fp
        PoofPlatform.setClipboardString(text)
        let item = Item(text: text, date: Date(), origin: .remote)
        remember(item)
        onIncoming?(item)
    }

    private func remember(_ item: Item) {
        history.insert(item, at: 0)
        if history.count > 3 {
            history.removeLast(history.count - 3)
        }
    }

    private func fingerprint(_ text: String) -> String {
        String(text.hashValue, radix: 16)
    }
}
