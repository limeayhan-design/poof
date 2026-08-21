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
        /// Contrat Secure fourni par l'expéditeur — nil = envoi standard.
        var secureConfig: SecureConfig?
        /// Contrat Track — signale au receiver d'émettre des read receipts
        /// enrichis (device, timestamp).
        var trackConfig: TrackConfig?
        /// Flag Boost : le payload transporté est compressé LZFSE et doit
        /// être décompressé avant matérialisation. Séparé de trackConfig/
        /// secureConfig car le compressé peut être combiné à n'importe quel
        /// contrat, y compris envoi standard sans Secure/Track.
        var compressed: Bool = false
    }

    var onIncomingMeta: ((Meta) -> Void)?
    var onProgress: ((_ id: UUID, _ bytes: UInt64, _ total: UInt64) -> Void)?
    var onCompleted: ((_ meta: Meta, _ fileURL: URL) -> Void)?
    var onCancelled: ((_ id: UUID, _ reason: String) -> Void)?
    var onDelivered: ((_ id: UUID) -> Void)?
    /// Read receipt reçu du destinataire — inclut le device et l'événement
    /// (opened) pour alimenter le Track côté sender.
    var onSeen: ((_ id: UUID, _ kind: TrackEvent.Kind, _ device: String?) -> Void)?
    var onSendStarted: ((_ meta: Meta) -> Void)?
    var onSendProgress: ((_ id: UUID, _ bytes: UInt64, _ total: UInt64) -> Void)?
    var onSendCompleted: ((_ meta: Meta) -> Void)?

    private weak var manager: PoofWebRTCManager?
    // Bumped from 1 MB → 4 MB : SCTP pipeline stays fuller, moins de stalls,
    // ~2-3x throughput sur Wi-Fi 5+ / Ethernet.
    private let backpressureLimit: UInt64 = 4_194_304
    private var incoming: [UUID: IncomingState] = [:]
    private var outgoing: [UUID: OutgoingState] = [:]
    private var resumeWaiters: [UUID: CheckedContinuation<UInt32, Never>] = [:]
    /// Chunks arrivés AVANT le fileMeta (WebRTC control channel unreliable,
    /// bulk channel plus rapide) — bufferisés jusqu'à ce qu'openIncoming
    /// crée le state, puis replay. Sans ça les 1-3 premiers chunks étaient
    /// silencieusement droppés → fichier reçu à 0 bytes.
    private var orphanChunks: [UUID: [PoofFrame.Decoded]] = [:]

    private final class IncomingState {
        let meta: Meta
        let handle: FileHandle
        let url: URL
        var expectedIndex: UInt32 = 0
        var receivedBytes: UInt64 = 0
        init(meta: Meta, handle: FileHandle, url: URL) {
            self.meta = meta
            self.handle = handle
            self.url = url
        }
    }

    private final class OutgoingState {
        let meta: Meta
        let sourceURL: URL
        var cancelled = false
        init(meta: Meta, sourceURL: URL) {
            self.meta = meta
            self.sourceURL = sourceURL
        }
    }

    init(manager: PoofWebRTCManager) {
        self.manager = manager
    }

    func send(
        fileAt url: URL,
        mime: String = "application/octet-stream",
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil,
        compressed: Bool = false,
        overrideName: String? = nil
    ) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let chunkCount = UInt32((size + UInt64(PoofFrame.chunkSize) - 1) / UInt64(PoofFrame.chunkSize))
        // overrideName = nom logique voulu par l'appelant (le fichier physique
        // sur le wire peut être compressé/chiffré, mais on veut préserver le
        // nom d'origine pour que le receiver retrouve `photo.jpg` et non
        // `photo.jpg.lzfse` sur son disque.
        let displayName = overrideName ?? url.lastPathComponent
        // Le meta transmis à `onSendStarted` DOIT porter les configs Secure
        // + Track — sinon `PoofSentFile.trackConfig` reste nil côté sender
        // et le gate `notifyOnOpen` bloque toutes les notifs Track à jamais.
        let meta = Meta(
            id: UUID(),
            name: displayName,
            size: size,
            mime: mime,
            chunkCount: chunkCount,
            secureConfig: secureConfig,
            trackConfig: trackConfig,
            compressed: compressed
        )
        let state = OutgoingState(meta: meta, sourceURL: url)
        outgoing[meta.id] = state
        defer { outgoing.removeValue(forKey: meta.id) }
        onSendStarted?(meta)

        var metaPayload: [String: Any] = [
            "name": meta.name,
            "size": Int(size),
            "mime": mime,
            "chunks": Int(chunkCount)
        ]
        // Envoi Secure — les métadonnées Secure sont sérialisées en JSON
        // dans un champ "secure" du payload fileMeta. Le receiver les lira
        // avant de matérialiser le fichier (voir PoofSession.onIncomingMeta).
        if let secureConfig,
           let json = try? JSONEncoder().encode(secureConfig),
           let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        {
            metaPayload["secure"] = dict
        }
        // Idem Track — clé "track" dans le payload fileMeta.
        if let trackConfig,
           let json = try? JSONEncoder().encode(trackConfig),
           let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        {
            metaPayload["track"] = dict
        }
        // Flag Boost compression — dit au receiver d'appliquer LZFSE decompress.
        if compressed {
            metaPayload["compressed"] = true
        }

        // Fiabilité — re-emit le fileMeta 3× avec 250ms de délai. Le control
        // channel est configuré `maxRetransmits: 0` (unreliable), un meta
        // perdu = receiver ne matérialise jamais le fichier. La redondance
        // 3× couvre les pertes réseau typiques (loss rate < 5%).
        let metaEnv = PoofEnvelope(
            type: .fileMeta,
            id: meta.id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: true,
            payload: metaPayload
        )
        manager?.sendEnvelope(metaEnv)
        Task { [weak manager] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            _ = manager?.sendEnvelope(metaEnv)
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = manager?.sendEnvelope(metaEnv)
        }
        // Le control channel (fileMeta) est unreliable, le bulk channel
        // (chunks) est reliable ordered. Sans delay, les 2 premiers chunks
        // peuvent arriver AVANT le meta chez le receiver → orphanChunks
        // maintenant les buffer, mais on garde une petite pause pour laisser
        // le receiver traiter le meta et se mettre en état de réception.
        try await Task.sleep(nanoseconds: 350_000_000)

        // Attend que le bulk channel soit ouvert avant de démarrer — sans ça
        // les tout premiers sendBulk retournent false et les chunks partent
        // dans le vide (fichier vide côté receiver).
        var bulkWait = 0
        while !(manager?.isBulkOpen ?? false), bulkWait < 60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            bulkWait += 1
        }
        guard manager?.isBulkOpen == true else {
            poofLog("[Poof] send abort — bulk channel never opened")
            return
        }

        var index: UInt32 = 0
        while true {
            if state.cancelled {
                return
            }

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

            // Retry local avec backpressure wait AVANT chaque tentative
            // (fix root cause : le buffer RTC interne peut être saturé même
            // si readyState == .open ; il faut attendre qu'il se vide entre
            // les retries, pas juste au premier envoi).
            var attempt = 0
            var sent = false
            while attempt < 10 {
                try await waitForBackpressure()
                if manager?.isBulkOpen == true, manager?.sendBulk(frame) == true {
                    sent = true
                    break
                }
                attempt += 1
                // Backoff : 50 → 100 → 200 → … jusqu'à ~5s max
                let delayMs = min(5000, 50 * (1 << attempt))
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
            guard sent else {
                poofLog("[Poof] send abort — chunk \(index) failed 10x, aborting")
                return
            }
            index &+= 1
            let sentBytes = min(size, UInt64(index) * UInt64(PoofFrame.chunkSize))
            onSendProgress?(meta.id, sentBytes, size)
            if isLast {
                break
            }
        }

        manager?.sendEnvelope(PoofEnvelope(
            type: .fileComplete,
            id: meta.id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: [:]
        ))
        onSendCompleted?(meta)
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

    /// Called by PoofSession when the WebRTC channel comes back up. For every
    /// outgoing transfer that stalled, ping the receiver so the send loop can
    /// wake up and jump to the right offset.
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
        // Poll intervalle 2 ms (au lieu de 5 ms) : plus réactif quand le
        // buffer descend, moins de temps mort entre 2 chunks.
        while let mgr = manager, mgr.bulkBufferedAmount > backpressureLimit {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Blocks until we receive a fileResumeAck for this transfer, or times out
    /// after ~30s of no recovery. Returns the resume index, or nil to abort.
    private func waitAndQueryResume(id: UUID) async -> UInt32? {
        // Poll for control-channel readiness (max 30s), then query the peer
        // and wait for its ack. Peer answers with fileResumeAck { expectedIndex }.
        let deadline = Date().addingTimeInterval(30)
        while !(manager?.isControlOpen ?? false) {
            if Date() > deadline {
                return nil
            }
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
                guard let self, let cont = resumeWaiters.removeValue(forKey: id) else { return }
                cont.resume(returning: UInt32.max)
            }
        }
        return ack == UInt32.max ? nil : ack
    }

    func handle(_ env: PoofEnvelope) {
        switch env.type {
        case .fileMeta: openIncoming(env)
        case .fileComplete: break
        case .fileCancel:
            if let id = UUID(uuidString: env.id) {
                cancel(id, reason: (env.payload["reason"] as? String) ?? "peer")
            }
        case .fileResumeQuery:
            respondResume(env)
        case .fileResumeAck:
            fulfilResume(env)
        case .fileDelivered:
            if let id = UUID(uuidString: env.id) {
                onDelivered?(id)
            }
        case .fileSeen:
            if let id = UUID(uuidString: env.id) {
                let rawKind = (env.payload["kind"] as? String) ?? TrackEvent.Kind.opened.rawValue
                let kind = TrackEvent.Kind(rawValue: rawKind) ?? .opened
                let device = env.payload["device"] as? String
                onSeen?(id, kind, device)
            }
        default: break
        }
    }

    func handle(frame: PoofFrame.Decoded) {
        guard let state = incoming[frame.transferId] else {
            // Meta pas encore reçu — buffer le chunk (cap 200 par transferId
            // pour ne pas exploser la RAM). On rejoue au moment de l'openIncoming.
            var buf = orphanChunks[frame.transferId] ?? []
            if buf.count < 200 {
                buf.append(frame)
                orphanChunks[frame.transferId] = buf
            }
            return
        }
        // Duplicate or stale frame from before a resume — safe to drop.
        if frame.index < state.expectedIndex {
            return
        }
        // Fiabilité : au lieu de cancel sur out-of-order (destruction du
        // transfert entier), on drop et laisse le sender rejouer via son
        // pipeline resume — beaucoup plus tolérant aux hics réseau.
        if frame.index > state.expectedIndex {
            return
        }
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
            let receivedFinal = state.receivedBytes
            let expected = state.meta.size
            incoming.removeValue(forKey: frame.transferId)

            // Rejet strict des fichiers partiels/vides — si les chunks du
            // milieu ont été perdus (out-of-order dropped, handshake casse,
            // buffer overflow), receivedBytes < expected. Matérialiser
            // produirait un placeholder confusant côté user.
            if expected > 0, receivedFinal < expected {
                poofLog("[Poof] receive rejected — got \(receivedFinal) B / \(expected) B expected, purging")
                try? FileManager.default.removeItem(at: state.url)
                onCancelled?(frame.transferId, "partial-transfer")
                return
            }

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

    /// Envoie un read receipt enrichi (device, kind) — utilisé par Track
    /// pour signaler une ouverture côté sender.
    func markSeen(_ id: UUID, kind: TrackEvent.Kind = .opened, device: String? = nil) {
        poofLog("[Poof] markSeen sending envelope — id=\(id) kind=\(kind.rawValue) device=\(device ?? "nil")")
        var payload: [String: Any] = ["kind": kind.rawValue]
        if let device {
            payload["device"] = device
        }
        manager?.sendEnvelope(PoofEnvelope(
            type: .fileSeen,
            id: id.uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: payload
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
        if incoming[id] != nil {
            return
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Poof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }

        // Récupération des contrats Secure et Track — sérialisés en JSON
        // dans les champs "secure" / "track" du payload fileMeta. Silencieux
        // si absent (envoi standard) ou malformé (on ne casse pas la réception).
        var secure: SecureConfig?
        if let raw = env.payload["secure"] as? [String: Any],
           let json = try? JSONSerialization.data(withJSONObject: raw),
           let decoded = try? JSONDecoder().decode(SecureConfig.self, from: json)
        {
            secure = decoded
        }
        var track: TrackConfig?
        if let raw = env.payload["track"] as? [String: Any],
           let json = try? JSONSerialization.data(withJSONObject: raw),
           let decoded = try? JSONDecoder().decode(TrackConfig.self, from: json)
        {
            track = decoded
        }

        let compressed = (env.payload["compressed"] as? Bool) ?? false
        let meta = Meta(
            id: id, name: name, size: size, mime: mime, chunkCount: chunks,
            secureConfig: secure, trackConfig: track, compressed: compressed
        )
        incoming[id] = IncomingState(meta: meta, handle: handle, url: url)
        onIncomingMeta?(meta)

        // Replay les chunks qui étaient arrivés AVANT le meta (buffer
        // orphelin). Sorted par index pour respecter l'ordre attendu.
        if let orphans = orphanChunks.removeValue(forKey: id) {
            let sorted = orphans.sorted { $0.index < $1.index }
            for frame in sorted {
                self.handle(frame: frame)
            }
        }
    }

    /// Receiver side of resume: reply with our expected next chunk index so
    /// the sender knows where to pick up. If we have no incoming state, answer 0.
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

    /// Sender side of resume: unblock the send loop with the target index.
    private func fulfilResume(_ env: PoofEnvelope) {
        guard let id = UUID(uuidString: env.id),
              let nextIndex = (env.payload["nextIndex"] as? NSNumber)?.uint32Value,
              let cont = resumeWaiters.removeValue(forKey: id) else { return }
        cont.resume(returning: nextIndex)
    }
}
