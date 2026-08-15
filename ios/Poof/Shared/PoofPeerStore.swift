import Foundation
import Combine

// Persistent list of paired peers (mirror of pc/src/paired-peer-store.js).

struct PairedPeer: Codable, Identifiable, Equatable {
    let id: String        // deviceId
    var name: String
    var platform: String
    var addedAt: Date
    var lastSeenAt: Date
}

@MainActor
final class PoofPeerStore: ObservableObject {
    private static let key = "poof.pairedPeers"

    @Published private(set) var peers: [PairedPeer] = []

    init() { load() }

    var ids: [String] { peers.map(\.id) }

    func has(_ id: String) -> Bool { peers.contains { $0.id == id } }

    func upsert(deviceId: String, name: String?, platform: String?) {
        var updated = peers
        if let idx = updated.firstIndex(where: { $0.id == deviceId }) {
            var p = updated[idx]
            if let name { p.name = name }
            if let platform { p.platform = platform }
            p.lastSeenAt = Date()
            updated[idx] = p
        } else {
            updated.append(PairedPeer(
                id: deviceId,
                name: name ?? "Unknown",
                platform: platform ?? "unknown",
                addedAt: Date(),
                lastSeenAt: Date()
            ))
        }
        peers = updated
        save()
    }

    func remove(_ id: String) {
        peers.removeAll { $0.id == id }
        save()
    }

    func touch(_ id: String) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].lastSeenAt = Date()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([PairedPeer].self, from: data) else { return }
        peers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(peers) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
