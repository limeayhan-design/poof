import Combine
import Foundation

// Persistent list of paired peers (mirror of pc/src/paired-peer-store.js).

struct PairedPeer: Codable, Identifiable, Equatable {
    let id: String // deviceId
    var name: String
    var platform: String
    var addedAt: Date
    var lastSeenAt: Date
}

@MainActor
final class PoofPeerStore: ObservableObject {
    private static let key = "poof.pairedPeers"

    @Published private(set) var peers: [PairedPeer] = []

    init() {
        load()
    }

    var ids: [String] {
        peers.map(\.id)
    }

    func has(_ id: String) -> Bool {
        peers.contains { $0.id == id }
    }

    func upsert(deviceId: String, name: String?, platform: String?) {
        // Normalise la casse — le serveur peut renvoyer un même deviceId
        // en majuscules OU minuscules selon le canal, ce qui crée sinon deux
        // entrées distinctes pour le même appareil.
        let normalized = deviceId.lowercased()
        // Ne jamais stocker soi-même comme peer — filet de sécurité contre un serveur
        // qui rediffuserait par erreur l'advertiser dans son propre pair-succeeded.
        guard normalized != PoofDeviceIdentity.deviceId.lowercased() else {
            poofLog("[Poof] peers.upsert refused self deviceId=\(deviceId)")
            return
        }
        var updated = peers
        if let idx = updated.firstIndex(where: { $0.id.lowercased() == normalized }) {
            var p = updated[idx]
            if let name {
                p.name = name
            }
            if let platform {
                p.platform = platform
            }
            p.lastSeenAt = Date()
            updated[idx] = p
        } else {
            updated.append(PairedPeer(
                id: normalized,
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

    func rename(_ id: String, to name: String) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].name = name
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
        // Purge un éventuel self stocké par une ancienne version buggée du serveur,
        // et déduplique par deviceId case-insensitive (le serveur peut varier la casse
        // selon le canal → deux entrées pour le même appareil).
        let selfId = PoofDeviceIdentity.deviceId.lowercased()
        var seen = Set<String>()
        var cleaned: [PairedPeer] = []
        for peer in decoded {
            let key = peer.id.lowercased()
            if key == selfId {
                continue
            }
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            var normalized = peer
            normalized = PairedPeer(
                id: key,
                name: peer.name,
                platform: peer.platform,
                addedAt: peer.addedAt,
                lastSeenAt: peer.lastSeenAt
            )
            cleaned.append(normalized)
        }
        peers = cleaned
        if cleaned.count != decoded.count || cleaned.map(\.id) != decoded.map(\.id) {
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(peers) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
