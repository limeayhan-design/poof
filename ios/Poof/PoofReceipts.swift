import Foundation

// Read-receipt state for a file we sent.
// sent    → the file left the device (frames pushed on bulk channel)
// delivered → peer wrote the last frame to disk (peer sent .fileDelivered)
// seen    → peer opened the file preview (peer sent .fileSeen)

nonisolated enum PoofReceiptState: String {
    case sent
    case delivered
    case seen

    var label: String {
        switch self {
        case .sent:      return "Sent"
        case .delivered: return "Delivered"
        case .seen:      return "Seen"
        }
    }

    var icon: String {
        switch self {
        case .sent:      return "checkmark"
        case .delivered: return "checkmark.circle.fill"
        case .seen:      return "eye.fill"
        }
    }
}

nonisolated struct PoofSentFile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let size: UInt64
    let peerId: String
    let peerName: String
    let date: Date
    var receipt: PoofReceiptState
    var deliveredAt: Date?
    var seenAt: Date?
}
