import Combine
import Foundation
import MultipeerConnectivity

/// Wrapper autour de `MultipeerConnectivity` pour l'envoi hors ligne — quand
/// le peer n'est pas joignable via WebRTC (mode avion, pas de réseau, etc.),
/// on repasse par ce canal pair-à-pair basé sur Bluetooth + Wi-Fi Direct.
///
/// L'API Apple gère automatiquement le choix du transport (Wi-Fi peer-to-peer,
/// Wi-Fi infrastructure, ou BT) — on lui donne juste les canaux autorisés.
/// Portée typique : jusqu'à 100 m en ligne directe via Wi-Fi Direct.
///
/// Limitations connues : `MCSession` est iOS/macOS/tvOS-only. Le cross-device
/// avec Android/Windows nécessiterait un protocole Core Bluetooth custom — hors
/// scope V1 (voir promise #5 « cross-device » du chip Offline).
@MainActor
final class PoofOfflineManager: NSObject, ObservableObject {
    /// Type de service Bonjour — 15 caractères max, minuscules + tirets.
    /// Doit matcher `NSBonjourServices` dans les 2 Info.plist.
    static let serviceType = "poof-offline"

    @Published private(set) var isAdvertising: Bool = false
    @Published private(set) var isBrowsing: Bool = false
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var lastReceivedURL: URL?
    @Published var toast: String?

    /// peerId Poof (stable) du device local. Injecté dans le `discoveryInfo`
    /// de MC pour que les browsers distants sachent qui advertise, et
    /// utilisé comme tie-break pour éviter les invitations mutuelles.
    var selfPeerPoofId: String?
    /// peerIds Poof des devices auto-connectables. Un peer découvert n'est
    /// invité automatiquement que si son `poofId` annoncé est dans ce set.
    /// Rempli par `PoofSession` depuis `OfflineConfig.linkedDeviceIds`.
    var targetPeerPoofIds: Set<String> = []
    /// Map peerId Poof → MCPeerID pour retrouver la session MC d'un device
    /// paired par son id stable au moment d'envoyer.
    @Published private(set) var peerPoofIdByMC: [MCPeerID: String] = [:]

    /// Callback déclenché quand un fichier finit d'arriver via MC — permet à
    /// `PoofSession` de matérialiser la ReceivedFile comme pour un WebRTC.
    var onIncomingFile: ((URL, String) -> Void)?

    private let peerId: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        let displayName = Self.currentDisplayName()
        peerId = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    /// Nom lisible affiché aux autres devices dans la découverte MC — dérivé
    /// du nom système (« iPhone de Uras »).
    private static func currentDisplayName() -> String {
        #if canImport(UIKit)
            return UIDevice.current.name
        #elseif canImport(AppKit)
            return Host.current().localizedName ?? "Mac"
        #else
            return "Device"
        #endif
    }

    // MARK: - Advertising (rend l'appareil découvrable)

    func startAdvertising() {
        guard !isAdvertising else { return }
        var discovery = ["app": "poof"]
        if let poofId = selfPeerPoofId {
            discovery["poofId"] = poofId
        }
        let adv = MCNearbyServiceAdvertiser(
            peer: peerId, discoveryInfo: discovery, serviceType: Self.serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        isAdvertising = true
    }

    /// Réémet l'advertising quand `selfPeerPoofId` ou `targetPeerPoofIds`
    /// changent après un premier start — sinon les infos annoncées restent
    /// figées à l'ancienne valeur.
    func restartAdvertisingIfNeeded() {
        guard isAdvertising else { return }
        stopAdvertising()
        startAdvertising()
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    // MARK: - Browsing (cherche les autres devices Poof à proximité)

    func startBrowsing() {
        guard !isBrowsing else { return }
        let b = MCNearbyServiceBrowser(peer: peerId, serviceType: Self.serviceType)
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

    // MARK: - Full stop

    func stopAll() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        connectedPeers = []
    }

    // MARK: - Invitation (initie une session avec un peer découvert)

    func invite(_ peer: MCPeerID, timeout: TimeInterval = 30) {
        guard let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: timeout)
    }

    // MARK: - Envoi fichier

    /// Envoie un fichier au premier peer connecté trouvé. Renvoie true si
    /// l'envoi a été initié. Chiffre le fichier E2E AES-256 avant transmission
    /// (couche additionnelle par-dessus le DTLS built-in de MCSession).
    /// La clé est dérivée du displayName des 2 peers (SHA256 trié).
    @discardableResult
    func sendFile(at url: URL, name: String, to peer: MCPeerID? = nil) -> Bool {
        let target = peer ?? connectedPeers.first
        guard let target else {
            toast = "No offline peer connected"
            return false
        }

        // Chiffrement E2E AES-256 — clé dérivée des displayNames des 2 peers
        // (SHA256 trié). Le fichier envoyé est le chiffré, le nom original
        // est conservé (le receiver déchiffre en place après réception).
        let key = SecureCrypto.sessionKey(
            localDeviceId: peerId.displayName,
            peerDeviceId: target.displayName
        )
        let payloadURL: URL
        do {
            payloadURL = try SecureCrypto.encryptFile(at: url, using: key)
        } catch {
            toast = "Offline encryption failed"
            return false
        }

        session.sendResource(at: payloadURL, withName: name, toPeer: target) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.toast = "Offline send failed: \(error.localizedDescription)"
                } else {
                    self?.toast = "Sent offline to \(target.displayName)"
                    PoofBetaCounter.shared.recordSuccessfulSend()
                }
            }
        }
        return true
    }

    /// Broadcast à tous les peers actuellement connectés. Utilisé quand
    /// l'utilisateur a sélectionné plusieurs devices dans « Linked offline
    /// devices » : chaque peer connecté reçoit sa propre copie chiffrée.
    /// Retourne le nombre d'envois initiés.
    @discardableResult
    func sendFileToAll(at url: URL, name: String) -> Int {
        let peers = connectedPeers
        guard !peers.isEmpty else {
            toast = "No offline peer connected"
            return 0
        }
        var count = 0
        for peer in peers where sendFile(at: url, name: name, to: peer) {
            count += 1
        }
        return count
    }
}

// MARK: - MCSessionDelegate

extension PoofOfflineManager: MCSessionDelegate {
    nonisolated func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                toast = "Offline: connected to \(peerID.displayName)"
            case .connecting:
                break
            case .notConnected:
                connectedPeers.removeAll { $0 == peerID }
            @unknown default: break
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive _: Data, fromPeer _: MCPeerID) {
        // Payload data channel non utilisé — Poof passe par les fichiers
        // dédiés (`didFinishReceivingResourceWithName`) pour un debit + reprise
        // gérés nativement par MC.
    }

    nonisolated func session(
        _: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID
    ) {}

    nonisolated func session(
        _: MCSession,
        didStartReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        with _: Progress
    ) {}

    nonisolated func session(
        _: MCSession,
        didFinishReceivingResourceWithName name: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                toast = "Offline receive failed: \(error.localizedDescription)"
                return
            }
            guard let localURL else { return }
            // MC nous donne un fichier temporaire — on le déplace dans le
            // dossier Poof pour que le pipeline standard (ReceivedFile) le récupère.
            let destDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Poof", isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let dest = destDir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: localURL, to: dest)
            // Déchiffre en place — le sender chiffre systématiquement pour
            // Offline (E2E AES-256 par-dessus le DTLS built-in de MCSession).
            // Clé dérivée des displayNames triés — les 2 peers arrivent au
            // même hash SHA256.
            let key = SecureCrypto.sessionKey(
                localDeviceId: peerId.displayName,
                peerDeviceId: peerID.displayName
            )
            do {
                try SecureCrypto.decryptInPlace(dest, using: key)
            } catch {
                toast = "Offline decryption failed"
                try? FileManager.default.removeItem(at: dest)
                return
            }
            lastReceivedURL = dest
            toast = "Offline file from \(peerID.displayName)"
            onIncomingFile?(dest, name)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PoofOfflineManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer _: MCPeerID,
        withContext _: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept — même paire d'appareils que le WebRTC (paired peers).
        // Pour un vrai V1 en prod on filtrerait par device ID connu.
        Task { @MainActor [weak self] in
            invitationHandler(true, self?.session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PoofOfflineManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?
    ) {
        let remotePoofId = info?["poofId"]
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !discoveredPeers.contains(peerID) {
                discoveredPeers.append(peerID)
            }
            if let remotePoofId {
                peerPoofIdByMC[peerID] = remotePoofId
            }
            // Auto-invite si le peer distant fait partie des devices présélectionnés
            // par l'utilisateur (targetPeerPoofIds). Tie-break sur le poofId Poof
            // stable — les 2 peers browse + advertise, un seul doit inviter
            // pour éviter la collision MC. L'advertiser côté cible auto-accept.
            guard let localPoofId = selfPeerPoofId,
                  let remotePoofId,
                  targetPeerPoofIds.contains(remotePoofId),
                  !connectedPeers.contains(peerID),
                  !session.connectedPeers.contains(peerID),
                  localPoofId < remotePoofId
            else { return }
            invite(peerID)
        }
    }

    nonisolated func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeAll { $0 == peerID }
            self?.peerPoofIdByMC.removeValue(forKey: peerID)
        }
    }
}

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
