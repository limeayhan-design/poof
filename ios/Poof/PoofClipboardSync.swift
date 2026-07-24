import Foundation
import UIKit

// Local clipboard bridge — mirrors pc/src/clipboard-sync.js.
// UIPasteboard.changedNotification only fires while foreground; manual push covers background.

final class PoofClipboardSync {

    struct Item: Equatable {
        let text: String
        let date: Date
        let origin: Origin
        enum Origin { case local, remote }
    }

    private(set) var history: [Item] = []
    var onIncoming: ((Item) -> Void)?

    // When false, silent clipboard changes are NOT auto-broadcast.
    // A user-triggered pushCurrent() still works either way.
    var autoPushEnabled: Bool = false

    private weak var manager: PoofWebRTCManager?
    private var lastLocalFingerprint: String?
    private var lastRemoteFingerprint: String?
    private var observer: NSObjectProtocol?

    init(manager: PoofWebRTCManager) {
        self.manager = manager
        observer = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleLocalChange(force: false) }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func pushCurrent() { handleLocalChange(force: true) }

    func handle(_ env: PoofEnvelope) {
        switch env.type {
        case .clipboard:      receive(env)
        case .clipboardAck:   break
        default:              break
        }
    }

    private func handleLocalChange(force: Bool) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        let fp = fingerprint(text)
        if fp == lastRemoteFingerprint { return }
        if !force, fp == lastLocalFingerprint { return }
        if !force, !autoPushEnabled { return }
        lastLocalFingerprint = fp

        remember(Item(text: text, date: Date(), origin: .local))

        let env = PoofEnvelope(
            type: .clipboard,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: force,
            payload: ["text": text, "fp": fp]
        )
        manager?.sendEnvelope(env)
    }

    private func receive(_ env: PoofEnvelope) {
        guard let text = env.payload["text"] as? String else { return }
        let fp = (env.payload["fp"] as? String) ?? fingerprint(text)
        lastRemoteFingerprint = fp
        UIPasteboard.general.string = text
        let item = Item(text: text, date: Date(), origin: .remote)
        remember(item)
        onIncoming?(item)
    }

    private func remember(_ item: Item) {
        history.insert(item, at: 0)
        if history.count > 3 { history.removeLast(history.count - 3) }
    }

    private func fingerprint(_ text: String) -> String {
        String(text.hashValue, radix: 16)
    }
}
