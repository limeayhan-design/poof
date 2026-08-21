import Foundation

/// Contrat Track — l'expéditeur veut savoir quand et par qui son fichier
/// a été ouvert, et attacher un message contextuel affiché au destinataire.
struct TrackConfig: Equatable, Codable {
    /// Historise chaque ouverture côté sender — badge compteur "eye" +
    /// entrée dans `trackEvents`. OFF = Track sert juste pour envoyer un
    /// customMessage sans laisser de trace côté sender.
    var readReceipts: Bool
    /// Notif système + toast à chaque ouverture. Indépendant de readReceipts :
    /// tu peux vouloir être notifié SANS historiser, ou historiser sans spam.
    var notifyOnOpen: Bool
    /// Message optionnel affiché au destinataire au-dessus du preview
    /// (ex. « Devis client - N° 12345 »). Nil = aucun message custom.
    var customMessage: String?

    /// Preset appliqué au 1er tap sur le chip Track — track de base actif,
    /// pas de message custom. L'utilisateur affine via long-press + sheet.
    static let defaults = TrackConfig(
        readReceipts: true,
        notifyOnOpen: true,
        customMessage: nil
    )
}

/// Événement observé côté sender (fichier ouvert par le destinataire).
/// Stocké dans PoofSession.trackEvents et exposé via toast + historique.
struct TrackEvent: Identifiable, Equatable, Codable {
    enum Kind: String, Codable, Equatable {
        case opened
    }

    var id: UUID
    var transferId: UUID
    var kind: Kind
    /// Nom lisible de l'appareil du destinataire ("iPhone de Léa"). Optionnel
    /// car l'ancien protocole `fileSeen` ne transportait rien de tel.
    var device: String?
    var timestamp: Date

    init(id: UUID = UUID(), transferId: UUID, kind: Kind, device: String? = nil, timestamp: Date = .init()) {
        self.id = id
        self.transferId = transferId
        self.kind = kind
        self.device = device
        self.timestamp = timestamp
    }
}
