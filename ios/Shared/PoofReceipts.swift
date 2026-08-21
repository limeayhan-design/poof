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
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .seen: "Seen"
        }
    }

    var icon: String {
        switch self {
        case .sent: "checkmark"
        case .delivered: "checkmark.circle.fill"
        case .seen: "eye.fill"
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
    /// Contrat Track appliqué à cet envoi — nil = envoi standard.
    /// Sert au sender pour respecter `notifyOnOpen` / `readReceipts` :
    /// on ne toast que si le contrat le prévoit.
    var trackConfig: TrackConfig?
}
