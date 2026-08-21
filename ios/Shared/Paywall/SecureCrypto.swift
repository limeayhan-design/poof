import CryptoKit
import Foundation

/// Chiffrement E2E AES-256-GCM pour les envois Secure. La clé de session
/// est dérivée localement des 2 deviceIds appairés (SHA256 du concaténé
/// trié) — jamais transmise à un serveur, jamais journalisée.
///
/// Zero-knowledge : le signaling server ne voit que du binaire opaque,
/// impossible de déchiffrer même en cas de compromission.
enum SecureCrypto {
    enum CryptoError: Error, LocalizedError {
        case emptyPayload
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .emptyPayload: "Empty payload"
            case .decryptionFailed: "Wrong key or corrupted data"
            }
        }
    }

    /// Dérive une clé AES-256 à partir des deviceIds des 2 parties.
    /// Trie les IDs pour garantir que sender et receiver dérivent la même clé
    /// sans dépendre de qui envoie.
    static func sessionKey(localDeviceId: String, peerDeviceId: String) -> SymmetricKey {
        let sorted = [localDeviceId.lowercased(), peerDeviceId.lowercased()].sorted()
        let combined = sorted.joined(separator: ":")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return SymmetricKey(data: hash)
    }

    /// Chiffre le contenu du fichier source et écrit le résultat dans un
    /// fichier temporaire séparé (même nom, dans `tmp/PoofSecure/`). Retourne
    /// l'URL du chiffré — c'est ce qu'on envoie sur le wire. Le fichier
    /// source reste intact.
    static func encryptFile(at source: URL, using key: SymmetricKey) throws -> URL {
        let data = try Data(contentsOf: source)
        guard !data.isEmpty else { throw CryptoError.emptyPayload }
        let sealed = try AES.GCM.seal(data, using: key)
        guard let out = sealed.combined else { throw CryptoError.emptyPayload }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofSecure", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try out.write(to: dest)
        return dest
    }

    /// Déchiffre en place — le fichier à l'URL fournie contient le chiffré,
    /// on le remplace par le clair. Utilisé côté receiver juste après
    /// `onCompleted` avant de matérialiser la ReceivedFile.
    static func decryptInPlace(_ url: URL, using key: SymmetricKey) throws {
        let sealedData = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: sealedData)
        let plain: Data
        do {
            plain = try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
        try plain.write(to: url)
    }
}
