import Foundation

/// Contrat Boost — lève les limites d'envoi (compte Free plafonné à 500 Mo)
/// et propose deux modifiers actifs à toggler par l'utilisateur :
/// compression sans perte + broadcast à tous les appareils appairés.
struct BoostConfig: Equatable, Codable {
    /// Compression LZFSE lossless client-side avant transfert. Le sender
    /// compresse via `BoostCompression.compressFile()`, le receiver décompresse
    /// via `decompressInPlace()` (flag `compressed` dans le fileMeta).
    var compression: Bool
    /// Envoi simultané à tous les appareils appairés (broadcast). Utilise
    /// l'infra `PoofSession.broadcastFile()` déjà en place, plutôt que
    /// `sendFile()` qui ne cible qu'un peer.
    var broadcastToAll: Bool

    /// Preset appliqué au 1er tap sur le chip Boost — compression ON pour
    /// gagner sur les transferts moyens, broadcast OFF pour ne pas envoyer
    /// à des destinataires non souhaités par défaut.
    static let defaults = BoostConfig(compression: true, broadcastToAll: false)
}
