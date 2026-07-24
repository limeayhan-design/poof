import Foundation
import SwiftUI
import Combine
import UIKit

// Runtime graph: Signaling ⇄ WebRTC ⇄ { Clipboard, File }.
// Exposed as ObservableObject so SwiftUI reacts to online peers, active session, pair code, etc.

@MainActor
final class PoofSession: ObservableObject {

    static var signalingURL: URL {
        if let saved = UserDefaults.standard.string(forKey: "poof.signalingURL"),
           let url = URL(string: saved) {
            return url
        }
        return URL(string: "http://192.168.129.174:3000")!
    }

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "poof.hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "poof.hasOnboarded") }
    }

    // MARK: Published state

    @Published var connectionState: String = "Idle"
    @Published var isSignalingConnected: Bool = false
    @Published var isRTCConnected: Bool = false
    @Published var onlinePeerIds: Set<String> = []
    @Published var pairCode: String? = nil
    @Published var pairError: String? = nil
    @Published var activePeerId: String? = nil
    @Published var lastIncomingText: String? = nil
    @Published var lastIncomingFile: URL? = nil
    @Published var incomingTransfer: TransferProgress? = nil
    @Published var toast: String? = nil
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var sentFiles: [PoofSentFile] = []
    @Published var universalClipboardEnabled: Bool = UserDefaults.standard.bool(forKey: "poof.universalClipboard") {
        didSet {
            UserDefaults.standard.set(universalClipboardEnabled, forKey: "poof.universalClipboard")
            clipboard.autoPushEnabled = universalClipboardEnabled
        }
    }

    struct TransferProgress: Equatable {
        var id: UUID
        var name: String
        var total: UInt64
        var received: UInt64
    }

    struct ReceivedFile: Identifiable, Equatable {
        let id: UUID
        let name: String
        let url: URL
        let size: UInt64
        let date: Date
    }

    // MARK: Graph

    let peers = PoofPeerStore()
    let manager = PoofWebRTCManager()
    public lazy var signaling = PoofSignalingClient(url: Self.signalingURL)
    public lazy var clipboard = PoofClipboardSync(manager: manager)
    public lazy var files = PoofFileTransfer(manager: manager)
    public lazy var remote = PoofRemoteFiles(manager: manager)
    public lazy var screenBroadcast = PoofScreenBroadcast(manager: manager)
    private let discovery = PoofDiscovery()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var userLeftSession = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var lastActivePeerId: String?
    private var reconnectTask: Task<Void, Never>?

    init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        Task { [weak self] in await self?.autoDiscoverGateway() }

        clipboard.autoPushEnabled = universalClipboardEnabled
        signaling.attach(manager)

        signaling.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        manager.onState = { [weak self] state in
            Task { @MainActor in self?.handle(state: state) }
        }
        manager.onEnvelope = { [weak self] env in
            self?.clipboard.handle(env)
            self?.files.handle(env)
            self?.remote.handle(env, fileTransfer: self?.files)
            self?.screenBroadcast.handle(env)
        }
        manager.onBulkFrame = { [weak self] frame in
            self?.files.handle(frame: frame)
        }

        clipboard.onIncoming = { [weak self] item in
            Task { @MainActor in
                self?.lastIncomingText = item.text
                self?.toast = "Clipboard received"
            }
        }
        files.onIncomingMeta = { [weak self] meta in
            Task { @MainActor in
                self?.incomingTransfer = TransferProgress(
                    id: meta.id, name: meta.name, total: meta.size, received: 0
                )
            }
        }
        files.onProgress = { [weak self] id, bytes, total in
            Task { @MainActor in
                guard var t = self?.incomingTransfer, t.id == id else { return }
                t.received = bytes
                self?.incomingTransfer = t
            }
        }
        files.onCompleted = { [weak self] meta, url in
            Task { @MainActor in
                guard let self else { return }
                self.incomingTransfer = nil
                self.lastIncomingFile = url
                self.toast = "File received: \(meta.name)"
                let entry = ReceivedFile(id: meta.id, name: meta.name, url: url, size: meta.size, date: Date())
                self.receivedFiles.insert(entry, at: 0)
                if self.receivedFiles.count > 30 {
                    self.receivedFiles.removeLast(self.receivedFiles.count - 30)
                }
            }
        }
        files.onCancelled = { [weak self] _, _ in
            Task { @MainActor in self?.incomingTransfer = nil }
        }
        files.onSendStarted = { [weak self] meta in
            Task { @MainActor in
                guard let self else { return }
                let (peerId, peerName) = self.activePeerInfo()
                let entry = PoofSentFile(
                    id: meta.id, name: meta.name, size: meta.size,
                    peerId: peerId, peerName: peerName, date: Date(),
                    receipt: .sent, deliveredAt: nil, seenAt: nil
                )
                self.sentFiles.insert(entry, at: 0)
                if self.sentFiles.count > 30 {
                    self.sentFiles.removeLast(self.sentFiles.count - 30)
                }
            }
        }
        files.onDelivered = { [weak self] id in
            Task { @MainActor in self?.updateReceipt(id: id, state: .delivered) }
        }
        files.onSeen = { [weak self] id in
            Task { @MainActor in self?.updateReceipt(id: id, state: .seen) }
        }

        signaling.connect()
    }

    // MARK: Actions

    func requestPairCode() {
        signaling.pairAdvertise { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let code):
                    self?.pairCode = code
                    self?.pairError = nil
                case .failure(let msg):
                    self?.pairError = msg.localizedDescription
                }
            }
        }
    }

    func cancelPair() {
        signaling.pairCancel()
        pairCode = nil
    }

    func joinWithCode(_ code: String) {
        signaling.pairConsume(code: code) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let peer):
                    self?.peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
                    self?.signaling.subscribe([peer.deviceId])
                    self?.openSession(with: peer.deviceId)
                case .failure(let msg):
                    self?.pairError = msg.localizedDescription
                }
            }
        }
    }

    func openSession(with deviceId: String) {
        if let current = activePeerId, current != deviceId {
            signaling.leaveSession()
            manager.close(reason: "switch")
        }
        activePeerId = deviceId
        lastActivePeerId = deviceId
        userLeftSession = false
        signaling.openSession(targetDeviceId: deviceId) { [weak self] result in
            Task { @MainActor in
                if case .failure(let msg) = result {
                    self?.toast = "Session failed: \(msg.localizedDescription)"
                    self?.activePeerId = nil
                }
            }
        }
    }

    func leaveSession() {
        userLeftSession = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        lastActivePeerId = nil
        signaling.leaveSession()
        manager.close(reason: "leave")
        activePeerId = nil
    }

    private func scheduleAutoReconnect(after seconds: Double) {
        guard !userLeftSession,
              let peerId = lastActivePeerId,
              reconnectAttempts < maxReconnectAttempts else {
            reconnectAttempts = 0
            return
        }
        reconnectAttempts += 1
        toast = "Reconnecting… (\(reconnectAttempts)/\(maxReconnectAttempts))"
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.isSignalingConnected,
                  self.onlinePeerIds.contains(peerId),
                  !self.userLeftSession else {
                self.reconnectAttempts = 0
                return
            }
            self.openSession(with: peerId)
        }
    }

    // Best-effort mDNS lookup for a Poof gateway on the LAN. If found and
    // different from the current URL, swap in the discovered endpoint. Silent
    // no-op on failure — the hardcoded/saved URL keeps working.
    private func autoDiscoverGateway() async {
        guard let endpoint = await discovery.find(timeout: 3.0),
              let url = endpoint.url else { return }
        if url.absoluteString == Self.signalingURL.absoluteString { return }
        print("[Poof] discovery: gateway @ \(url.absoluteString)")
        updateSignalingURL(url)
    }

    func updateSignalingURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "poof.signalingURL")
        guard started else { return }
        signaling.disconnect()
        manager.close(reason: "url-change")
        signaling = PoofSignalingClient(url: url)
        signaling.attach(manager)
        signaling.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        activePeerId = nil
        onlinePeerIds = []
        pairCode = nil
        signaling.connect()
    }

    func completeOnboarding() {
        Self.hasOnboarded = true
    }

    func enterBackground() {
        guard started else { return }
        print("[Poof] app backgrounded — disconnecting signaling")
        userLeftSession = true
        reconnectTask?.cancel()
        signaling.leaveSession()
        manager.close(reason: "background")
        signaling.disconnect()
        isSignalingConnected = false
        isRTCConnected = false
        activePeerId = nil
        onlinePeerIds = []
    }

    func returnToForeground() {
        guard started else { return }
        print("[Poof] app foregrounded — reconnecting signaling")
        userLeftSession = false
        signaling.connect()
    }

    func unpair(_ deviceId: String) {
        if activePeerId == deviceId { leaveSession() }
        signaling.broadcastUnpair(deviceId)
        signaling.unsubscribe([deviceId])
        onlinePeerIds.remove(deviceId)
        peers.remove(deviceId)
    }

    func isPeerOnline(_ id: String) -> Bool {
        let target = id.lowercased()
        return onlinePeerIds.contains(where: { $0.lowercased() == target })
    }

    func pushClipboard() { clipboard.pushCurrent() }

    /// Notify the sender that we opened the file preview — flips receipt to .seen.
    func markSeen(_ id: UUID) { files.markSeen(id) }

    private func activePeerInfo() -> (String, String) {
        guard let id = activePeerId,
              let peer = peers.peers.first(where: { $0.id == id }) else {
            return ("", "Unknown")
        }
        return (peer.id, peer.name)
    }

    private func updateReceipt(id: UUID, state: PoofReceiptState) {
        guard let idx = sentFiles.firstIndex(where: { $0.id == id }) else { return }
        var entry = sentFiles[idx]
        // Never downgrade (seen > delivered > sent)
        let order: [PoofReceiptState] = [.sent, .delivered, .seen]
        let currentRank = order.firstIndex(of: entry.receipt) ?? 0
        let newRank = order.firstIndex(of: state) ?? 0
        guard newRank >= currentRank else { return }
        entry.receipt = state
        if state == .delivered, entry.deliveredAt == nil { entry.deliveredAt = Date() }
        if state == .seen, entry.seenAt == nil { entry.seenAt = Date() }
        sentFiles[idx] = entry
    }

    /// Push whatever is on the pasteboard (text or image). Returns a human-readable
    /// summary of what was pushed, or nil if the pasteboard was empty / unsupported.
    /// Premium+ feature — image path writes a temp PNG and sends via file transfer.
    @discardableResult
    func pushClipboardRich() -> String? {
        if let text = UIPasteboard.general.string, !text.isEmpty {
            clipboard.pushCurrent()
            return "Text sent"
        }
        if let image = UIPasteboard.general.image,
           let png = image.pngData() {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PoofOutgoing", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let name = "clipboard-\(Int(Date().timeIntervalSince1970)).png"
            let dest = tempDir.appendingPathComponent(name)
            do {
                try png.write(to: dest)
                sendFile(at: dest, mime: "image/png")
                return "Image sent"
            } catch {
                return nil
            }
        }
        return nil
    }

    func clearHistory() {
        for entry in receivedFiles { try? FileManager.default.removeItem(at: entry.url) }
        receivedFiles = []
    }

    func sendText(_ text: String) {
        let env = PoofEnvelope(
            type: .clipboard,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: true,
            payload: ["text": text, "fp": String(text.hashValue, radix: 16)]
        )
        manager.sendEnvelope(env)
    }

    func sendFile(at url: URL, mime: String = "application/octet-stream") {
        Task { try? await files.send(fileAt: url, mime: mime) }
    }

    // Drains files enqueued by the Share Extension. Runs on launch and on
    // every `poof://share` URL open. Waits (bounded) for the WebRTC channel
    // to be up so shares taken while offline are held until reconnection.
    func drainSharedInbox() async {
        let pending = SharedStore.loadQueue()
        guard !pending.isEmpty else { return }

        let deadline = Date().addingTimeInterval(15)
        while !isRTCConnected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard isRTCConnected else {
            toast = "Shared \(pending.count) item(s) — will send when connected"
            return
        }

        for item in pending {
            guard let url = SharedStore.fileURL(for: item) else { continue }
            do {
                try await files.send(fileAt: url, mime: item.mime)
                SharedStore.remove(item.id)
            } catch {
                toast = "Share failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Event routing

    private func handle(_ event: PoofSignalingClient.Event) {
        switch event {
        case .connected:
            isSignalingConnected = true
            connectionState = "Waiting for peer…"
            sayHello()
        case .disconnected(let r):
            isSignalingConnected = false
            connectionState = "Offline (\(r))"
        case .peerOnline(let id):
            print("[Poof] peer-online \(id)")
            onlinePeerIds.insert(id)
            peers.touch(id)
            if activePeerId == nil, !userLeftSession, peers.has(id) {
                openSession(with: id)
            }
        case .peerOffline(let id):
            print("[Poof] peer-offline \(id)")
            onlinePeerIds.remove(id)
        case .pairSucceeded(let peer):
            peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
            signaling.subscribe([peer.deviceId])
            onlinePeerIds.insert(peer.deviceId)
            pairCode = nil
            toast = "Paired with \(peer.name)"
        case .pairExpired:
            pairCode = nil
        case .sessionOpened(_, _, let from):
            connectionState = "Session opening…"
            reconnectAttempts = 0
            if let from {
                activePeerId = from
                lastActivePeerId = from
                userLeftSession = false
            }
        case .sessionClosed(_, let r), .peerLeft(_, let r):
            connectionState = "Session closed (\(r))"
            isRTCConnected = false
            activePeerId = nil
            if shouldAutoReconnect(reason: r) {
                scheduleAutoReconnect(after: 1.5)
            }
        case .peerUnpaired(let id):
            print("[Poof] peer-unpaired \(id)")
            if activePeerId == id { leaveSession() }
            onlinePeerIds.remove(id)
            peers.remove(id)
            toast = "A paired device removed you"
        case .error(let msg):
            connectionState = "Error: \(msg)"
        }
    }

    private func handle(state: PoofWebRTCManager.State) {
        switch state {
        case .idle:
            connectionState = "Idle"
        case .connecting:
            connectionState = "Connecting…"
        case .connected:
            connectionState = "Online"
            isRTCConnected = true
            reconnectAttempts = 0
            // Wake up any file sends that were paused waiting for the
            // channel — receiver will hand back its expected chunk index.
            files.resumeAllActiveSends()
        case .closed(let reason):
            connectionState = "Offline (\(reason))"
            isRTCConnected = false
            if shouldAutoReconnect(reason: reason) {
                scheduleAutoReconnect(after: 1.5 * Double(max(reconnectAttempts, 1)))
            }
        }
    }

    private func shouldAutoReconnect(reason: String) -> Bool {
        if userLeftSession { return false }
        let transient = ["ice-failed", "ice-disconnected", "peer-left", "peer-disconnected", "peer-closed"]
        return transient.contains(where: { reason.contains($0) })
    }

    private func sayHello() {
        let known = peers.ids
        print("[Poof] hello knownPeerIds=\(known) deviceId=\(PoofDeviceIdentity.deviceId)")
        signaling.hello(
            deviceId: PoofDeviceIdentity.deviceId,
            name: PoofDeviceIdentity.name,
            platform: PoofDeviceIdentity.platform,
            knownPeerIds: known
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let onlinePeers):
                    print("[Poof] hello ok onlinePeers=\(onlinePeers.map(\.deviceId))")
                    self.onlinePeerIds = Set(onlinePeers.map(\.deviceId))
                    for peer in onlinePeers {
                        self.peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
                    }
                case .failure(let err):
                    print("[Poof] hello FAILED \(err.localizedDescription)")
                }
                let knownIds = self.peers.ids
                if !knownIds.isEmpty {
                    print("[Poof] subscribing to \(knownIds)")
                    self.signaling.subscribe(knownIds)
                }
                self.maybeAutoConnect()
            }
        }
    }

    private func maybeAutoConnect() {
        guard activePeerId == nil, !userLeftSession else { return }
        // Prefer known-online peers first
        if let peer = peers.peers
            .sorted(by: { $0.lastSeenAt > $1.lastSeenAt })
            .first(where: { onlinePeerIds.contains($0.id) }) {
            openSession(with: peer.id)
            return
        }
        // Fallback: probe most-recent paired peer even if server didn't
        // report them online — server may not implement peer-online events.
        if let peer = peers.peers.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first {
            probeAndOpen(peerId: peer.id)
        }
    }

    private func probeAndOpen(peerId: String) {
        print("[Poof] probing paired peer \(peerId)")
        activePeerId = peerId
        lastActivePeerId = peerId
        userLeftSession = false
        signaling.openSession(targetDeviceId: peerId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    print("[Poof] probe succeeded, peer is online")
                    self.onlinePeerIds.insert(peerId)
                case .failure(let err):
                    print("[Poof] probe failed \(err.localizedDescription)")
                    self.activePeerId = nil
                }
            }
        }
    }
}
