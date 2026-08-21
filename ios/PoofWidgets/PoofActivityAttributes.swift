#if os(iOS)
    import ActivityKit
    import Foundation

    // Live Activity contract — copie EXACTE de ios/Shared/PoofActivityAttributes.swift
    // pour que le target PoofWidgets compile le type. Le folder Shared est
    // synchronized-referenced par les targets Poof/PoofMac mais PAS par
    // PoofWidgets (qui n'inclut que son propre dossier). Sans cette copie
    // le widget target ne connaît pas PoofTransferAttributes → aucune Live
    // Activity ne s'enregistre → Dynamic Island reste vide.
//
    // ⚠️ Toute modification du contract (champs de Attributes ou ContentState)
    // doit être répliquée dans les 2 fichiers en même temps.

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
