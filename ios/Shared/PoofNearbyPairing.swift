import Combine
import Foundation
import MultipeerConnectivity

/// Discovery + pairing pair-à-pair via MultipeerConnectivity (BT + Wi-Fi
/// Direct + Wi-Fi infra), style AirDrop. L'app advertise en permanence (dès
/// `PoofSession.start()`) pour être « trouvable » par tout autre device Poof
/// à proximité, et browse seulement quand l'utilisateur ouvre le sheet Add
/// Device (économie batterie).
///
/// Flow d'appairage sans code :
/// 1. Les 2 devices advertise sur le service `poof-pair` avec discoveryInfo
///    = leur deviceId Poof stable + name + platform.
/// 2. Sender tap un peer dans la liste "Nearby" → `invite(peer:)`.
/// 3. Receiver : le delegate advertise reçoit l'invitation → on publie une
///    `pendingInvitation` que `NearbyInvitationSheet` affiche globalement
///    (n'importe où dans l'app, pas seulement Add Device).
/// 4. Accept → session MC ouverte → les 2 devices s'ajoutent mutuellement
///    au `PoofPeerStore` avec le deviceId annoncé dans discoveryInfo.
/// 5. Session MC fermée dans la foulée — MC a servi juste au handshake, le
///    vrai transport reste WebRTC + relay HTTPS.
@MainActor
final class PoofNearbyPairing: NSObject, ObservableObject {
    static let shared = PoofNearbyPairing()

    /// Service type MC — 15 char max, minuscules + tirets. Doit être dans
    /// `NSBonjourServices` du Info.plist (déjà présent : `_poof-pair._tcp/udp`).
    /// Séparé de `poof-offline` pour ne pas mixer les 2 flows (offline
    /// nécessite d'être déjà paired, pairing est une phase antérieure).
    static let serviceType = "poof-pair"

    struct DiscoveredPeer: Identifiable, Equatable {
        let id: String
        let mcPeerId: MCPeerID
        let deviceId: String
        let name: String
        let platform: String

        var kind: DeviceKind {
            switch platform.lowercased() {
            case "ios", "ipados": name.lowercased().contains("ipad") ? .ipad : .iphone
            case "macos", "osx": .macbook
            default: .iphone
            }
        }
    }

    struct PendingInvitation: Identifiable {
        let id = UUID()
        let mcPeerId: MCPeerID
        let fromName: String
        let fromDeviceId: String
        let fromPlatform: String
        let respond: (Bool) -> Void
    }

    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published var pendingInvitation: PendingInvitation?
    @Published private(set) var isBrowsing: Bool = false
    @Published private(set) var isAdvertising: Bool = false
    @Published var toast: String?

    /// Callback branché par `PoofSession` — appelé quand un pairing réussit
    /// (côté sender OU receiver). L'implémentation ajoute le peer au
    /// `PoofPeerStore`, subscribe au signaling et ouvre la session WebRTC.
    var onPairingComplete: ((_ deviceId: String, _ name: String, _ platform: String) -> Void)?

    private let localPeerId: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// deviceId Poof local — injecté dans le discoveryInfo pour que les peers
    /// distants apprennent notre identité stable dès la découverte.
    var localDeviceId: String = ""

    override init() {
        let name = Self.currentDeviceName()
        localPeerId = MCPeerID(displayName: name)
        session = MCSession(peer: localPeerId, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    private static func currentDeviceName() -> String {
        #if canImport(UIKit)
            return UIDevice.current.name
        #elseif canImport(AppKit)
            return Host.current().localizedName ?? "Mac"
        #else
            return "Device"
        #endif
    }

    // MARK: - Advertising (permanent — dès PoofSession.start())

    func startAdvertising(deviceId: String) {
        localDeviceId = deviceId
        guard !isAdvertising else { return }
        let info: [String: String] = [
            "deviceId": deviceId,
            "platform": PoofPlatform.platform,
            "name": localPeerId.displayName
        ]
        let adv = MCNearbyServiceAdvertiser(
            peer: localPeerId, discoveryInfo: info, serviceType: Self.serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    // MARK: - Browsing (opt-in — quand Add Device ouvert)

    func startBrowsing() {
        guard !isBrowsing else { return }
        let b = MCNearbyServiceBrowser(peer: localPeerId, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        isBrowsing = true
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        discoveredPeers = []
    }

    // MARK: - Invite (sender → receiver)

    /// Envoie une invitation MC à un peer découvert. L'advertiser distant
    /// reçoit `didReceiveInvitationFromPeer` et publie une `PendingInvitation`
    /// qui déclenche l'affichage global d'un sheet accept/deny.
    func invite(_ peer: DiscoveredPeer, timeout: TimeInterval = 30) {
        guard let browser else { return }
        // Encode notre deviceId Poof dans le context — le receiver n'a pas
        // besoin de re-browse pour connaître notre id stable après accept.
        let context = try? JSONSerialization.data(withJSONObject: [
            "deviceId": localDeviceId,
            "platform": PoofPlatform.platform,
            "name": localPeerId.displayName
        ])
        browser.invitePeer(peer.mcPeerId, to: session, withContext: context, timeout: timeout)
        toast = "Request sent to \(peer.name)…"
    }
}

// MARK: - MCSessionDelegate

extension PoofNearbyPairing: MCSessionDelegate {
    nonisolated func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                // La session MC est ouverte — sur l'iPhone qui a envoyé l'invite,
                // c'est le signal que le receiver a accepté. On envoie notre
                // deviceId Poof en payload pour que le receiver l'associe au
                // MCPeerID reçu (le context d'invite ne parvient qu'au receiver).
                let payload: [String: String] = [
                    "deviceId": localDeviceId,
                    "platform": PoofPlatform.platform,
                    "name": localPeerId.displayName
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload) {
                    try? session.send(data, toPeers: [peerID], with: .reliable)
                }
            case .notConnected, .connecting:
                break
            @unknown default: break
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let deviceId = json["deviceId"], !deviceId.isEmpty
            else { return }
            let name = json["name"] ?? peerID.displayName
            let platform = json["platform"] ?? "unknown"
            onPairingComplete?(deviceId, name, platform)
            toast = "Paired with \(name)"
            // Le handshake est fini — MC ne sert plus. On déconnecte pour
            // libérer BT/Wi-Fi et éviter les collisions avec l'Offline manager.
            session.disconnect()
        }
    }

    nonisolated func session(
        _: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID
    ) {}

    nonisolated func session(
        _: MCSession, didStartReceivingResourceWithName _: String,
        fromPeer _: MCPeerID, with _: Progress
    ) {}

    nonisolated func session(
        _: MCSession,
        didFinishReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        at _: URL?,
        withError _: Error?
    ) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PoofNearbyPairing: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Extrait le deviceId + name du sender depuis le context (envoyé par
        // le sender dans `invite()`). Si absent, on utilise juste le displayName.
        var fromDeviceId = ""
        var fromName = peerID.displayName
        var fromPlatform = "unknown"
        if let context,
           let json = try? JSONSerialization.jsonObject(with: context) as? [String: String]
        {
            fromDeviceId = json["deviceId"] ?? ""
            fromName = json["name"] ?? fromName
            fromPlatform = json["platform"] ?? fromPlatform
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Publie la demande en attente — le modifier `nearbyInvitationSheet`
            // affiche un sheet global (n'importe où dans l'app).
            let request = PendingInvitation(
                mcPeerId: peerID,
                fromName: fromName,
                fromDeviceId: fromDeviceId,
                fromPlatform: fromPlatform,
                respond: { [weak self] accepted in
                    guard let self else { return }
                    invitationHandler(accepted, accepted ? session : nil)
                    if accepted, !fromDeviceId.isEmpty {
                        // Le receiver connaît déjà l'id du sender via context —
                        // on ajoute immédiatement le peer sans attendre le send
                        // du sender (qui arrive en parallèle sur la MCSession).
                        onPairingComplete?(fromDeviceId, fromName, fromPlatform)
                    }
                    pendingInvitation = nil
                }
            )
            pendingInvitation = request
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PoofNearbyPairing: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?
    ) {
        let deviceId = info?["deviceId"] ?? ""
        let name = info?["name"] ?? peerID.displayName
        let platform = info?["platform"] ?? "unknown"
        guard !deviceId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Ne pas afficher notre propre device (même deviceId Poof).
            guard deviceId != localDeviceId else { return }
            let peer = DiscoveredPeer(
                id: deviceId, mcPeerId: peerID,
                deviceId: deviceId, name: name, platform: platform
            )
            if !discoveredPeers.contains(peer) {
                discoveredPeers.append(peer)
            }
        }
    }

    nonisolated func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeAll { $0.mcPeerId == peerID }
        }
    }
}

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
