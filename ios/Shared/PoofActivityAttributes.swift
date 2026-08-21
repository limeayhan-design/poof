#if os(iOS)
    import ActivityKit
    import Foundation

    // Live Activity contract shared between the main Poof app and the PoofWidgets
    // extension. The `Attributes` values are static for the life of the transfer
    // (filename, peer name, direction). The `ContentState` values tick as bytes
    // stream — the Widget target reads them to redraw the Dynamic Island / Lock
    // Screen UI in real time.

    public struct PoofTransferAttributes: ActivityAttributes {
        public enum Direction: String, Codable, Hashable, Sendable {
            case send, receive
        }

        public struct ContentState: Codable, Hashable, Sendable {
            public var received: UInt64
            public var isFinished: Bool
            public var didFail: Bool

            public init(received: UInt64, isFinished: Bool = false, didFail: Bool = false) {
                self.received = received
                self.isFinished = isFinished
                self.didFail = didFail
            }
        }

        public let transferId: String
        public let fileName: String
        public let totalBytes: UInt64
        public let peerName: String
        public let direction: Direction
        public let startedAt: Date

        public init(
            transferId: String,
            fileName: String,
            totalBytes: UInt64,
            peerName: String,
            direction: Direction,
            startedAt: Date = Date()
        ) {
            self.transferId = transferId
            self.fileName = fileName
            self.totalBytes = totalBytes
            self.peerName = peerName
            self.direction = direction
            self.startedAt = startedAt
        }
    }

    public extension PoofTransferAttributes.ContentState {
        func fraction(of total: UInt64) -> Double {
            guard total > 0 else { return isFinished ? 1 : 0 }
            return min(1.0, Double(received) / Double(total))
        }
    }
#endif
