import Foundation

// Wire protocol — must match pc/src/poof-protocol.js exactly.

nonisolated enum PoofMessageType: String, Codable {
    case clipboard
    case clipboardAck
    case notification
    case notificationReply
    case notificationAction
    case handoff
    case handoffAck
    case fileMeta
    case fileComplete
    case fileCancel
    case fileResumeQuery
    case fileResumeAck
    case fileDelivered
    case fileSeen
    case fileWipe
    case remoteListRequest
    case remoteListResponse
    case remoteGetRequest
    case ping
    case pong
}

nonisolated struct PoofEnvelope {
    let type: PoofMessageType
    let id: String
    let ts: TimeInterval
    let force: Bool
    let payload: [String: Any]

    func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": type.rawValue,
            "id": id,
            "ts": ts,
            "force": force,
            "payload": payload
        ], options: [])
    }

    static func decode(_ data: Data) throws -> PoofEnvelope {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["type"] as? String,
              let type = PoofMessageType(rawValue: raw),
              let id = root["id"] as? String,
              let ts = root["ts"] as? TimeInterval
        else {
            throw PoofProtocolError.malformed
        }
        return PoofEnvelope(
            type: type,
            id: id,
            ts: ts,
            force: (root["force"] as? Bool) ?? false,
            payload: (root["payload"] as? [String: Any]) ?? [:]
        )
    }
}

nonisolated enum PoofProtocolError: Error {
    case malformed
    case unsupportedType
}

// Binary framing — must match CHUNK_SIZE + HEADER_SIZE in poof-protocol.js.
// Layout: [16B transferUUID][4B chunkIndex BE][1B flags][payload ≤ 128 KiB]
// Chunk size bumpé à 128 KB pour ~2x moins de messages sur SCTP → throughput
// ~2x supérieur. 128 KB reste bien sous la limite spec WebRTC (256 KB).
nonisolated enum PoofFrame {
    static let chunkSize = 128 * 1024
    static let headerSize = 21

    static func encode(transferId: UUID, index: UInt32, isLast: Bool, payload: Data) -> Data {
        var out = Data(capacity: headerSize + payload.count)
        withUnsafeBytes(of: transferId.uuid) { out.append(contentsOf: $0) }
        var beIndex = index.bigEndian
        withUnsafeBytes(of: &beIndex) { out.append(contentsOf: $0) }
        out.append(isLast ? 0x01 : 0x00)
        out.append(payload)
        return out
    }

    struct Decoded {
        let transferId: UUID
        let index: UInt32
        let isLast: Bool
        let payload: Data
    }

    static func decode(_ frame: Data) throws -> Decoded {
        guard frame.count >= headerSize else { throw PoofProtocolError.malformed }
        let uuidBytes: uuid_t = frame.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 0, as: uuid_t.self)
        }
        let indexBE: UInt32 = frame.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 16, as: UInt32.self)
        }
        let flags = frame[20]
        return Decoded(
            transferId: UUID(uuid: uuidBytes),
            index: UInt32(bigEndian: indexBE),
            isLast: (flags & 0x01) != 0,
            payload: frame.subdata(in: headerSize ..< frame.count)
        )
    }
}
