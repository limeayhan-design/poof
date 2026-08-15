import Foundation

// Chunk-based file transfer over the bulk data channel.
// Flow: sender emits fileMeta on control, streams binary frames on bulk, then fileComplete.
// Backpressure: keeps in-flight bytes under 1 MiB.
//
// Resume: sender keeps active send state in memory. If the WebRTC channel
// goes down mid-stream, the send loop pauses; on `resumeAllActiveSends()`
// it queries the receiver for its expected index and jumps ahead. Receiver
// tracks partial state per transferId so resume is idempotent.

final class PoofFileTransfer {

    struct Meta {
        let id: UUID
        let name: String
        let size: UInt64
        let mime: String
        let chunkCount: UInt32
    }

    var onIncomingMeta: ((Meta) -> Void)?
    var onProgress: ((_ id: UUID, _ bytes: UInt64, _ total: UInt64) -> Void)?
    var onCompleted: ((_ meta: Meta, _ fileURL: URL) -> Void)?
    var onCancelled: ((_ id: UUID, _ reason: String) -> Void)?
    var onDelivered: ((_ id: UUID) -> Void)?
    var onSeen: ((_ id: UUID) -> Void)?
    var onSendStarted: ((_ meta: Meta) -> Void)?

    private weak var manager: PoofWebRTCManager?
    private let backpressureLimit: UInt64 = 1_048_576
    private var incoming: [UUID: IncomingState] = [:]
    private var outgoing: [UUID: OutgoingState] = [:]
    private var resumeWaiters: [UUID: CheckedContinuation<UInt32, Never>] = [:]

    private final class IncomingState {
        let meta: Meta
        let handle: FileHandle
        let url: URL
        var expectedIndex: UInt32 = 0
        var receivedBytes: UInt64 = 0
        init(meta: Meta, handle: FileHandle, url: URL) {
            self.meta = meta; self.handle = handle; self.url = url
        }
    }

    private final class OutgoingState {
        let meta: Meta
        let sourceURL: URL
        var cancelled = false
        init(meta: Meta, sourceURL: URL) { self.meta = meta; self.sourceURL = sourceURL }
    }

    init(manager: PoofWebRTCManager) { self.manager = manager }

    func send(fileAt url: URL, mime: String = "application/octet-stream") async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let chunkCount = UInt32((size + UInt64(PoofFrame.chunkSize) - 1) / UInt64(PoofFrame.chunkSize))
        let meta = Meta(id: UUID(), name: url.lastPathComponent, size: size, mime: mime, chunkCount: chunkCount)
        let state = OutgoingState(meta: meta, sourceURL: url)
        outgoing[meta.id] = state
        defer { outgoing.removeValue(forKey: meta.id) }
        onSendStarted?(meta)

        manager?.sendEnvelope(PoofEnvelope(
            type: .fileMeta,
            id: meta.id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["name": meta.name, "size": Int(size), "mime": mime, "chunks": Int(chunkCount)]
        ))

        var index: UInt32 = 0
        while true {
            if state.cancelled { return }

            // If the bulk channel is unavailable, pause and — once it comes
            // back — ask the receiver where to resume. Bounded wait; if we
            // never recover, abort the send.
            if !(manager?.isBulkOpen ?? false) {
                guard let target = await waitAndQueryResume(id: meta.id) else { return }
                index = target
                try handle.seek(toOffset: UInt64(index) * UInt64(PoofFrame.chunkSize))
            }

            let payload = handle.readData(ofLength: PoofFrame.chunkSize)
            let isLast = payload.count < PoofFrame.chunkSize
            let frame = PoofFrame.encode(transferId: meta.id, index: index, isLast: isLast, payload: payload)
            try await waitForBackpressure()
            _ = manager?.sendBulk(frame)
            index &+= 1
            if isLast { break }
        }

        manager?.sendEnvelope(PoofEnvelope(
            type: .fileComplete,
            id: meta.id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: [:]
        ))
    }

    func cancel(_ id: UUID, reason: String = "user") {
        outgoing[id]?.cancelled = true
        manager?.sendEnvelope(PoofEnvelope(
            type: .fileCancel,
            id: id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["reason": reason]
        ))
        if let state = incoming.removeValue(forKey: id) {
            try? state.handle.close()
            try? FileManager.default.removeItem(at: state.url)
            onCancelled?(id, reason)
        }
    }

    // Called by PoofSession when the WebRTC channel comes back up. For every
    // outgoing transfer that stalled, ping the receiver so the send loop can
    // wake up and jump to the right offset.
    func resumeAllActiveSends() {
        for id in outgoing.keys {
            manager?.sendEnvelope(PoofEnvelope(
                type: .fileResumeQuery,
                id: id.uuidString,
                ts: Date().timeIntervalSince1970,
                force: false,
                payload: [:]
            ))
        }
    }

    private func waitForBackpressure() async throws {
        while let mgr = manager, mgr.bulkBufferedAmount > backpressureLimit {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // Blocks until we receive a fileResumeAck for this transfer, or times out
    // after ~30s of no recovery. Returns the resume index, or nil to abort.
    private func waitAndQueryResume(id: UUID) async -> UInt32? {
        // Poll for control-channel readiness (max 30s), then query the peer
        // and wait for its ack. Peer answers with fileResumeAck { expectedIndex }.
        let deadline = Date().addingTimeInterval(30)
        while !(manager?.isControlOpen ?? false) {
            if Date() > deadline { return nil }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let ack: UInt32 = await withCheckedContinuation { (cont: CheckedContinuation<UInt32, Never>) in
            self.resumeWaiters[id] = cont
            self.manager?.sendEnvelope(PoofEnvelope(
                type: .fileResumeQuery,
                id: id.uuidString,
                ts: Date().timeIntervalSince1970,
                force: false,
                payload: [:]
            ))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, let cont = self.resumeWaiters.removeValue(forKey: id) else { return }
                cont.resume(returning: UInt32.max)
            }
        }
        return ack == UInt32.max ? nil : ack
    }

    func handle(_ env: PoofEnvelope) {
        switch env.type {
        case .fileMeta:      openIncoming(env)
        case .fileComplete:  break
        case .fileCancel:
            if let id = UUID(uuidString: env.id) { cancel(id, reason: (env.payload["reason"] as? String) ?? "peer") }
        case .fileResumeQuery:
            respondResume(env)
        case .fileResumeAck:
            fulfilResume(env)
        case .fileDelivered:
            if let id = UUID(uuidString: env.id) { onDelivered?(id) }
        case .fileSeen:
            if let id = UUID(uuidString: env.id) { onSeen?(id) }
        default: break
        }
    }

    func handle(frame: PoofFrame.Decoded) {
        guard let state = incoming[frame.transferId] else { return }
        // Duplicate or stale frame from before a resume — safe to drop.
        if frame.index < state.expectedIndex { return }
        guard frame.index == state.expectedIndex else {
            cancel(frame.transferId, reason: "out-of-order")
            return
        }
        state.handle.write(frame.payload)
        state.expectedIndex &+= 1
        state.receivedBytes &+= UInt64(frame.payload.count)
        onProgress?(frame.transferId, state.receivedBytes, state.meta.size)

        if frame.isLast {
            try? state.handle.close()
            incoming.removeValue(forKey: frame.transferId)
            onCompleted?(state.meta, state.url)
            manager?.sendEnvelope(PoofEnvelope(
                type: .fileDelivered,
                id: frame.transferId.uuidString,
                ts: Date().timeIntervalSince1970,
                force: false,
                payload: [:]
            ))
        }
    }

    func markSeen(_ id: UUID) {
        manager?.sendEnvelope(PoofEnvelope(
            type: .fileSeen,
            id: id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: [:]
        ))
    }

    private func openIncoming(_ env: PoofEnvelope) {
        guard let id = UUID(uuidString: env.id),
              let name = env.payload["name"] as? String,
              let size = (env.payload["size"] as? NSNumber)?.uint64Value,
              let mime = env.payload["mime"] as? String,
              let chunks = (env.payload["chunks"] as? NSNumber)?.uint32Value else { return }

        // If a receive is already in flight for this id (e.g. sender is
        // re-announcing after reconnect), keep the existing partial state.
        if incoming[id] != nil { return }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Poof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }

        let meta = Meta(id: id, name: name, size: size, mime: mime, chunkCount: chunks)
        incoming[id] = IncomingState(meta: meta, handle: handle, url: url)
        onIncomingMeta?(meta)
    }

    // Receiver side of resume: reply with our expected next chunk index so
    // the sender knows where to pick up. If we have no incoming state, answer 0.
    private func respondResume(_ env: PoofEnvelope) {
        guard let id = UUID(uuidString: env.id) else { return }
        let nextIndex = incoming[id]?.expectedIndex ?? 0
        manager?.sendEnvelope(PoofEnvelope(
            type: .fileResumeAck,
            id: env.id,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["nextIndex": Int(nextIndex)]
        ))
    }

    // Sender side of resume: unblock the send loop with the target index.
    private func fulfilResume(_ env: PoofEnvelope) {
        guard let id = UUID(uuidString: env.id),
              let nextIndex = (env.payload["nextIndex"] as? NSNumber)?.uint32Value,
              let cont = resumeWaiters.removeValue(forKey: id) else { return }
        cont.resume(returning: nextIndex)
    }
}
