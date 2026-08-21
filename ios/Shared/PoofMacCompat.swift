#if canImport(AppKit)
    import Foundation

    final class PoofLiveActivityController {
        static let shared = PoofLiveActivityController()
        private init() {}
        func startSend(id _: String, name _: String, total _: UInt64, peerName _: String) {}
        func startReceive(id _: String, name _: String, total _: UInt64, peerName _: String) {}
        func updateSend(id _: String, bytes _: UInt64) {}
        func updateReceive(id _: String, bytes _: UInt64) {}
        func endSend(id _: String, success _: Bool) {}
        func endReceive(id _: String, success _: Bool) {}
        func endAllOrphans() {}
    }

    enum AirGap {
        static var enabled: Bool {
            false
        }

        static func isLAN(_: URL) -> Bool {
            true
        }
    }

    enum KidControls {
        static var enabled: Bool {
            false
        }

        static func isInQuietHours(now _: Date = Date()) -> Bool {
            false
        }
    }

    final class PoofRemoteFiles {
        init(manager _: PoofWebRTCManager) {}
        func handle(_: PoofEnvelope, fileTransfer _: PoofFileTransfer?) {}
    }
#endif
