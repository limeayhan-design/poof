import Foundation
import UIKit
import Combine

// Live screen mirror bridge.
// The Broadcast Upload Extension writes JPEG frames + status flag to the App Group
// container and fires Darwin notifications. We watch that channel here and forward
// each frame over the WebRTC control channel as a `screenMirrorFrame` envelope with
// base64 JPEG payload. Control channel is `maxRetransmits=0, isOrdered=false` — a
// dropped frame is preferable to a stalled queue.
//
// Also handles incoming frames — decodes base64 → UIImage → publishes latestFrame.

@MainActor
final class PoofScreenBroadcast: ObservableObject {

    static let appGroupId = "group.com.atlas.link.poof"
    static let frameFilename = "screen-mirror.jpg"
    static let statusFilename = "screen-mirror.status"
    static let frameNotification = "com.atlas.link.poof.screenMirror.frame"
    static let statusNotification = "com.atlas.link.poof.screenMirror.status"

    @Published var isBroadcasting: Bool = false
    @Published var isReceiving: Bool = false
    @Published var latestFrame: UIImage? = nil
    @Published var latestFrameAt: Date? = nil

    private weak var manager: PoofWebRTCManager?
    private var frameObserver: CFNotificationObserver?
    private var statusObserver: CFNotificationObserver?
    private var pollTask: Task<Void, Never>?
    private var lastForwardedAt: CFTimeInterval = 0
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId)
    }

    // Wrapper so we can register Darwin observers using MainActor-isolated callbacks.
    final class CFNotificationObserver {
        let observer: UnsafeRawPointer
        init(_ observer: UnsafeRawPointer) { self.observer = observer }
        deinit {
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer
            )
        }
    }

    init(manager: PoofWebRTCManager) {
        self.manager = manager
        readStatusFromDisk()
        registerObservers()
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Broadcast lifecycle (sender side)

    private func readStatusFromDisk() {
        guard let url = containerURL?.appendingPathComponent(Self.statusFilename),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            isBroadcasting = false
            return
        }
        isBroadcasting = data.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func registerObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let ptr = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center, ptr,
            { _, ptr, _, _, _ in
                guard let ptr else { return }
                let me = Unmanaged<PoofScreenBroadcast>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in me.handleFrameNotification() }
            },
            Self.frameNotification as CFString,
            nil,
            .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, ptr,
            { _, ptr, _, _, _ in
                guard let ptr else { return }
                let me = Unmanaged<PoofScreenBroadcast>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in me.handleStatusNotification() }
            },
            Self.statusNotification as CFString,
            nil,
            .deliverImmediately
        )

        frameObserver = CFNotificationObserver(ptr)
        statusObserver = CFNotificationObserver(ptr)

        // Poll fallback — Darwin notifications can be coalesced when app is inactive.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self?.pollTick()
            }
        }
    }

    private func pollTick() {
        readStatusFromDisk()
        if isBroadcasting { handleFrameNotification() }
    }

    private func handleStatusNotification() {
        let wasBroadcasting = isBroadcasting
        readStatusFromDisk()
        if isBroadcasting && !wasBroadcasting {
            sendStart()
        } else if !isBroadcasting && wasBroadcasting {
            sendStop()
        }
    }

    private func handleFrameNotification() {
        guard isBroadcasting, let url = containerURL?.appendingPathComponent(Self.frameFilename),
              let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let now = CACurrentMediaTime()
        guard now - lastForwardedAt >= 0.05 else { return } // hard cap at ~20 FPS
        lastForwardedAt = now
        forwardFrame(data)
    }

    private func forwardFrame(_ jpeg: Data) {
        guard let manager, manager.isControlOpen else { return }
        let env = PoofEnvelope(
            type: .screenMirrorFrame,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["jpeg": jpeg.base64EncodedString()]
        )
        manager.sendEnvelope(env)
    }

    private func sendStart() {
        manager?.sendEnvelope(PoofEnvelope(
            type: .screenMirrorStart,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: true,
            payload: [:]
        ))
    }

    private func sendStop() {
        manager?.sendEnvelope(PoofEnvelope(
            type: .screenMirrorStop,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: true,
            payload: [:]
        ))
    }

    // MARK: - Receiver side

    func handle(_ env: PoofEnvelope) {
        switch env.type {
        case .screenMirrorStart:
            isReceiving = true
        case .screenMirrorStop:
            isReceiving = false
            latestFrame = nil
        case .screenMirrorFrame:
            guard let b64 = env.payload["jpeg"] as? String,
                  let data = Data(base64Encoded: b64),
                  let image = UIImage(data: data) else { return }
            latestFrame = image
            latestFrameAt = Date()
            if !isReceiving { isReceiving = true }
        default:
            break
        }
    }
}
