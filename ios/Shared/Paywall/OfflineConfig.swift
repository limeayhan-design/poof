import Foundation

/// Contrat Offline — active la découverte pair-à-pair (Bluetooth + Wi-Fi
/// Direct via `MultipeerConnectivity`) et le routage automatique des envois
/// vers ce canal quand le peer WebRTC n'est pas joignable via internet.
struct OfflineConfig: Equatable, Codable {
    /// Rend cet appareil découvrable par les autres appareils Poof à proximité.
    /// Sans ça, on ne peut recevoir aucun envoi hors ligne, même si l'envoyeur
    /// nous cherche activement.
    var advertise: Bool
    /// Autorise l'utilisation du canal Bluetooth Classic (portée ~10 m, plus
    /// lent mais universel). Utile en mode avion Wi-Fi coupé mais BT ouvert.
    var allowBluetooth: Bool
    /// Autorise Wi-Fi Direct / peer-to-peer Wi-Fi (portée ~100 m, débit élevé).
    /// Requis pour envoyer des fichiers > quelques Mo dans un délai raisonnable.
    var allowWifi: Bool
    /// peerIds Poof des devices présélectionnés par l'utilisateur (via la
    /// section « Linked offline devices » du sheet). Quand le sender part en
    /// mode Offline, on n'auto-invite QUE les MC peers dont le poofId annoncé
    /// figure dans ce set → broadcast possible à plusieurs devices sans
    /// autoriser des inconnus à intercepter le flux.
    var linkedDeviceIds: Set<String>

    /// Preset appliqué au 1er tap sur le chip Offline — les 2 canaux ouverts,
    /// l'appareil est découvrable pour recevoir. Modifiable via long-press.
    static let defaults = OfflineConfig(
        advertise: true, allowBluetooth: true, allowWifi: true, linkedDeviceIds: []
    )
}
