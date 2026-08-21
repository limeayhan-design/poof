import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// Runtime graph: Signaling ⇄ WebRTC ⇄ { Clipboard, File }.
// Exposed as ObservableObject so SwiftUI reacts to online peers, active session, pair code, etc.

@MainActor
final class PoofSession: ObservableObject {
    static var signalingURL: URL {
        // Force Render officiel — la lecture du custom UserDefaults a été
        // retirée car autoDiscoverGateway pouvait sauver une IP LAN obsolète
        // (serveur Poof PC arrêté depuis, VPN, etc.) qui bloquait la
        // connexion des devices au signaling → devices=1 dans /health,
        // pairing impossible. Solution automatique : bypass UserDefaults.
        URL(string: "https://poof-fgb8.onrender.com")!
    }

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "poof.hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "poof.hasOnboarded") }
    }

    // MARK: Published state

    @Published var connectionState: String = "Idle"
    @Published var isSignalingConnected: Bool = false
    @Published var isRTCConnected: Bool = false
    @Published var onlinePeerIds: Set<String> = []
    @Published var pairCode: String? = nil
    @Published var pairError: String? = nil
    @Published var activePeerId: String? = nil
    @Published var lastIncomingText: String? = nil
    @Published var lastIncomingFile: URL? = nil
    @Published var incomingTransfer: TransferProgress? = nil
    @Published var toast: String? = nil
    @Published var receivedFiles: [ReceivedFile] = []
    @Published var sentFiles: [PoofSentFile] = []
    @Published var pendingKidReview: PendingKidReview?
    /// Historique des Track events par transferId — ouvertures et screenshots
    /// signalés par le destinataire. Vidé au restart pour rester privacy-first.
    @Published var trackEvents: [UUID: [TrackEvent]] = [:]
    @Published var universalClipboardEnabled: Bool = UserDefaults.standard.bool(forKey: "poof.universalClipboard") {
        didSet {
            UserDefaults.standard.set(universalClipboardEnabled, forKey: "poof.universalClipboard")
            clipboard.autoPushEnabled = universalClipboardEnabled
        }
    }

    struct TransferProgress: Equatable {
        var id: UUID
        var name: String
        var total: UInt64
        var received: UInt64
    }

    struct ReceivedFile: Identifiable, Equatable {
        let id: UUID
        let name: String
        let url: URL
        let size: UInt64
        let date: Date
        /// Contrat de sécurité fourni par l'expéditeur — nil = envoi standard.
        /// Sur un envoi Secure, les règles (passcode, expiry, one-time,
        /// biometrics, watermark) doivent être appliquées avant toute preview.
        var secureConfig: SecureConfig?
        /// Contrat Track — si non nil, le receiver émettra des read receipts
        /// enrichis au sender et observera les screenshots pendant la lecture.
        var trackConfig: TrackConfig?
        /// Date d'ouverture (first view) — utilisée par one-time view pour
        /// détecter le second accès et purger le fichier.
        var openedAt: Date?
        /// Local identifiers des PHAssets créés quand l'utilisateur a
        /// sauvegardé le fichier dans sa galerie Photos. À l'expiration, on
        /// les supprime aussi de la galerie — sinon la promesse « auto-destruct »
        /// serait bypass par un simple Save.
        var savedAssetIds: [String] = []

        /// Date exacte à laquelle le fichier expire. Nil = never.
        /// Presets (oneHour, oneDay, etc.) sont ancrés à la date de réception.
        /// `.customDate` renvoie directement la date absolue choisie par
        /// l'expéditeur (ne bouge pas selon quand on la lit).
        var expiryDate: Date? {
            guard let policy = secureConfig?.expiry else { return nil }
            switch policy {
            case .never: return nil
            case let .customDate(target): return target
            case .oneHour: return date.addingTimeInterval(60 * 60)
            case .oneDay: return date.addingTimeInterval(60 * 60 * 24)
            case .sevenDays: return date.addingTimeInterval(60 * 60 * 24 * 7)
            case .thirtyDays: return date.addingTimeInterval(60 * 60 * 24 * 30)
            }
        }

        /// Vrai si l'expiry est dépassée. Un fichier expiré doit être
        /// supprimé automatiquement et non ouvrable. Basé sur `expiryDate`
        /// pour éviter le bug qui existait avec `.customDate` où la duration
        /// était recalculée à chaque check et se croisait à mi-parcours.
        var isExpired: Bool {
            guard let expiryDate else { return false }
            return Date() >= expiryDate
        }
    }

    struct PendingKidReview: Identifiable, Equatable {
        let id: UUID
        let name: String
        let size: UInt64
        let peerName: String
        let url: URL
    }

    // MARK: Graph

    let peers = PoofPeerStore()
    let manager = PoofWebRTCManager()
    lazy var signaling = PoofSignalingClient(url: Self.signalingURL)
    lazy var clipboard = PoofClipboardSync(manager: manager)
    lazy var files = PoofFileTransfer(manager: manager)
    lazy var remote = PoofRemoteFiles(manager: manager)
    let offline = PoofOfflineManager()
    private let discovery = PoofDiscovery()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var userLeftSession = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var lastActivePeerId: String?
    private var reconnectTask: Task<Void, Never>?
    private var secureSweepTask: Task<Void, Never>?
    /// Capture le peerId au moment où le fileMeta arrive — on l'utilise au
    /// decrypt Secure car activePeerId peut avoir été reset entre-temps
    /// (peer déconnecté juste après le transfert).
    private var transferPeerIds: [UUID: String] = [:]

    /// Filtre `receivedFiles` pour retirer toutes les entrées dont le fichier
    /// physique est absent ou 0 bytes — évite d'afficher des placeholders
    /// génériques pour des envois passés qui ont échoué.
    private func purgeEmptyReceivedFiles() {
        let fm = FileManager.default
        receivedFiles.removeAll { entry in
            let size = (try? fm.attributesOfItem(atPath: entry.url.path)[.size] as? Int) ?? 0
            let missing = !fm.fileExists(atPath: entry.url.path)
            return missing || size == 0
        }
    }

    /// Supprime les fichiers 0 bytes qui traînent dans tmp/Poof/ (créés
    /// par openIncoming avant que le transfert échoue). Sans ça ils
    /// s'accumulent sur disque à chaque envoi raté.
    private func cleanupEmptyTmpFiles() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Poof", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in files {
            let url = dir.appendingPathComponent(name)
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size == 0 {
                try? fm.removeItem(at: url)
            }
        }
    }

    init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        // Cleanup préventif : efface un signalingURL LAN custom qui aurait
        // été sauvé par une version précédente (autoDiscoverGateway). Sans
        // ça les 2 devices pouvaient rester bloqués sur une IP LAN morte
        // et /health remontait devices:1 au lieu de 2.
        UserDefaults.standard.removeObject(forKey: "poof.signalingURL")

        // Sweep any Live Activity left over from a previous crash before the
        // first hook fires — otherwise a new send stacks on top of a stale one.
        PoofLiveActivityController.shared.endAllOrphans()

        // Purge des fichiers fantômes 0-bytes (envois passés qui ont échoué
        // silencieusement) — sinon ils restent affichés dans Received tiles
        // avec un placeholder générique confusant.
        purgeEmptyReceivedFiles()

        // Nettoyage disque : supprime aussi les .jpg orphelins 0-bytes dans
        // le tmp de l'app sandbox (fichiers créés par openIncoming avant fail).
        cleanupEmptyTmpFiles()

        // Rediffuse les changements de PoofPeerStore au niveau session pour que
        // les vues observant `session` réagissent aux pairings — sinon SwiftUI
        // ne re-render pas quand seul un ObservableObject imbriqué change.
        peers.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Devium Air-gap désactivé + auto-discovery LAN gateway désactivé.
        // autoDiscoverGateway pouvait sauver une IP LAN dans UserDefaults et
        // bloquer la reconnexion au signaling Render à chaque re-launch.
        // On force toujours Render officiel pour éviter les états incohérents.

        clipboard.autoPushEnabled = universalClipboardEnabled
        signaling.attach(manager)

        signaling.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        // Sync avatar + displayName cross-device : quand l'utilisateur change
        // sa photo (PhotosPicker) ou son nom, on push aux autres devices du
        // même compte iCloud via signaling. Re-hello aussi pour taguer notre
        // socket avec le bon appleUserId côté serveur (nécessaire au broadcast).
        PoofProfileImage.shared.onLocalChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sayHello()
                self.pushLocalAvatarIfPossible()
            }
        }
        // Load initial (Mac : Me Card ; iOS : no-op — attend le sync remote)
        PoofProfileImage.shared.loadIfNeeded()

        // Nearby pairing (AirDrop-style) — advertising permanent pour être
        // découvrable dès l'app ouverte. Le browsing démarre à l'ouverture
        // du sheet Add Device. Callback : ajoute juste le peer + subscribe.
        // On n'appelle PAS openSession ici : les 2 devices déclencheraient
        // simultanément un `session-open` → collision serveur → toast
        // "Session failed" (le fichier passe quand même via relay HTTPS).
        // Le flow normal `maybeAutoConnect` ouvrira la WebRTC quand
        // nécessaire (au 1er envoi), ou l'user peut le faire manuellement.
        PoofNearbyPairing.shared.onPairingComplete = { [weak self] deviceId, name, platform in
            Task { @MainActor in
                guard let self else { return }
                self.peers.upsert(deviceId: deviceId, name: name, platform: platform)
                self.signaling.subscribe([deviceId])
                // Re-hello pour que le serveur mette à jour notre liste de
                // peers connus + nous réponde avec l'état online du nouveau
                // peer. Sans ça, le user peut taper le device juste après
                // pairing → openSession → serveur répond "offline" (le peer
                // distant n'a pas encore émis son propre hello à jour).
                self.sayHello()
                self.persistLastPeerToAppGroup(deviceId: deviceId, name: name)
                self.toast = "Paired with \(name)"
            }
        }
        PoofNearbyPairing.shared.startAdvertising(deviceId: PoofDeviceIdentity.deviceId)

        // Persiste l'identité self dans le App Group pour que les App Intents
        // (Action Button / Siri / Control Center widget) puissent envoyer
        // au bon deviceId sans dépendre de l'app main être ouverte.
        persistSelfIdentityToAppGroup()
        manager.onState = { [weak self] state in
            Task { @MainActor in self?.handle(state: state) }
        }
        manager.onEnvelope = { [weak self] env in
            self?.clipboard.handle(env)
            self?.files.handle(env)
            self?.remote.handle(env, fileTransfer: self?.files)
        }
        manager.onBulkFrame = { [weak self] frame in
            self?.files.handle(frame: frame)
        }

        clipboard.onIncoming = { [weak self] item in
            Task { @MainActor in
                self?.lastIncomingText = item.text
                self?.toast = "Clipboard received"
            }
        }
        files.onIncomingMeta = { [weak self] meta in
            Task { @MainActor in
                guard let self else { return }
                // Capture le peerId ACTIF au moment du meta — on l'utilisera
                // au decrypt Secure même si le peer s'est déconnecté entre.
                if let pid = self.activePeerId ?? self.lastActivePeerId {
                    self.transferPeerIds[meta.id] = pid
                }
                self.incomingTransfer = TransferProgress(
                    id: meta.id, name: meta.name, total: meta.size, received: 0
                )
                let (_, peerName) = self.activePeerInfo()
                PoofLiveActivityController.shared.startReceive(
                    id: meta.id.uuidString, name: meta.name, total: meta.size, peerName: peerName
                )
            }
        }
        files.onProgress = { [weak self] id, bytes, _ in
            Task { @MainActor in
                guard var t = self?.incomingTransfer, t.id == id else { return }
                t.received = bytes
                self?.incomingTransfer = t
                PoofLiveActivityController.shared.updateReceive(id: id.uuidString, bytes: bytes)
            }
        }
        files.onCompleted = { [weak self] meta, url in
            Task { @MainActor in
                guard let self else { return }
                self.incomingTransfer = nil
                PoofLiveActivityController.shared.endReceive(id: meta.id.uuidString, success: true)

                if PoofTier.current == .family, KidControls.enabled {
                    if KidControls.isInQuietHours() {
                        try? FileManager.default.removeItem(at: url)
                        self.toast = "Blocked · quiet hours"
                        return
                    }
                    let peerName = self.peers.peers.first(where: { $0.id == self.activePeerId })?.name ?? "a device"
                    self.pendingKidReview = PendingKidReview(
                        id: meta.id, name: meta.name, size: meta.size, peerName: peerName, url: url
                    )
                    self.toast = "New file needs your approval"
                    return
                }

                // Pipeline receiver miroir du sender : decrypt (Secure) →
                // decompress (Boost) → matérialiser. Chaque étape est opt-in
                // via un flag du payload fileMeta.
                // Fix : fallback sur lastActivePeerId si activePeerId est déjà
                // nil (peer déconnecté juste après la fin du transfert). Sans
                // ce fallback, le decrypt était SKIP silencieusement et le
                // fichier restait chiffré → preview cassée côté receiver.
                if meta.secureConfig != nil {
                    // Priorité : peerId capturé au meta > activePeerId courant
                    // > lastActivePeerId. Le premier est le plus fiable car
                    // capturé quand la connexion était vivante.
                    let peerId = self.transferPeerIds[meta.id]
                        ?? self.activePeerId
                        ?? self.lastActivePeerId
                    guard let peerId else {
                        self.toast = "Decryption failed: no peer id"
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    let key = SecureCrypto.sessionKey(
                        localDeviceId: PoofDeviceIdentity.deviceId,
                        peerDeviceId: peerId
                    )
                    do {
                        try SecureCrypto.decryptInPlace(url, using: key)
                    } catch {
                        self.toast = "Decryption failed"
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                }
                self.transferPeerIds.removeValue(forKey: meta.id)
                if meta.compressed {
                    do {
                        try BoostCompression.decompressInPlace(url)
                    } catch {
                        self.toast = "Decompression failed"
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                }

                self.acceptReceivedFile(
                    id: meta.id,
                    name: meta.name,
                    url: url,
                    size: meta.size,
                    secureConfig: meta.secureConfig,
                    trackConfig: meta.trackConfig
                )
            }
        }
        files.onCancelled = { [weak self] id, _ in
            Task { @MainActor in
                self?.incomingTransfer = nil
                PoofLiveActivityController.shared.endReceive(id: id.uuidString, success: false)
                PoofLiveActivityController.shared.endSend(id: id.uuidString, success: false)
            }
        }
        files.onSendStarted = { [weak self] meta in
            Task { @MainActor in
                guard let self else { return }
                let (peerId, peerName) = self.activePeerInfo()
                let entry = PoofSentFile(
                    id: meta.id, name: meta.name, size: meta.size,
                    peerId: peerId, peerName: peerName, date: Date(),
                    receipt: .sent, deliveredAt: nil, seenAt: nil,
                    trackConfig: meta.trackConfig
                )
                self.sentFiles.insert(entry, at: 0)
                if self.sentFiles.count > 30 {
                    self.sentFiles.removeLast(self.sentFiles.count - 30)
                }
                PoofLiveActivityController.shared.startSend(
                    id: meta.id.uuidString, name: meta.name, total: meta.size, peerName: peerName
                )
            }
        }
        files.onSendProgress = { id, bytes, _ in
            Task { @MainActor in
                PoofLiveActivityController.shared.updateSend(id: id.uuidString, bytes: bytes)
            }
        }
        files.onSendCompleted = { meta in
            Task { @MainActor in
                PoofLiveActivityController.shared.endSend(id: meta.id.uuidString, success: true)
            }
        }
        files.onDelivered = { [weak self] id in
            Task { @MainActor in self?.updateReceipt(id: id, state: .delivered) }
        }
        files.onSeen = { [weak self] id, kind, device in
            poofLog("[Poof] onSeen received — id=\(id) kind=\(kind.rawValue) device=\(device ?? "nil")")
            Task { @MainActor in
                guard let self else { return }
                self.updateReceipt(id: id, state: .seen)
                self.recordTrackEvent(TrackEvent(
                    transferId: id, kind: kind, device: device
                ))
            }
        }

        // Offline (MultipeerConnectivity) — un fichier reçu via BT / Wi-Fi
        // Direct passe par le même pipeline `acceptReceivedFile` que WebRTC.
        offline.onIncomingFile = { [weak self] url, name in
            Task { @MainActor in
                guard let self else { return }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
                    .uint64Value ?? 0
                self.acceptReceivedFile(id: UUID(), name: name, url: url, size: size)
            }
        }

        // Timer de sweep expiry — tourne toutes les 60s pour purger les
        // fichiers Secure dont la durée de vie est atteinte, même sans
        // action utilisateur ni retour au premier plan. Suffisant pour un
        // "auto-destruct" perçu comme instantané par l'utilisateur.
        secureSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await MainActor.run { self?.sweepExpiredSecureFiles() }
            }
        }

        signaling.connect()
    }

    // MARK: Actions

    func requestPairCode() {
        signaling.pairAdvertise { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(code):
                    self?.pairCode = code
                    self?.pairError = nil
                case let .failure(msg):
                    self?.pairError = msg.localizedDescription
                }
            }
        }
    }

    func cancelPair() {
        signaling.pairCancel()
        pairCode = nil
    }

    func joinWithCode(
        _ code: String,
        completion: ((Result<PoofSignalingClient.Peer, PoofSignalingError>) -> Void)? = nil
    ) {
        signaling.pairConsume(code: code) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(peer):
                    self?.peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
                    self?.signaling.subscribe([peer.deviceId])
                    self?.openSession(with: peer.deviceId)
                    completion?(.success(peer))
                case let .failure(msg):
                    self?.pairError = msg.localizedDescription
                    completion?(.failure(msg))
                }
            }
        }
    }

    func openSession(with deviceId: String) {
        if let current = activePeerId, current != deviceId {
            signaling.leaveSession()
            manager.close(reason: "switch")
        }
        activePeerId = deviceId
        lastActivePeerId = deviceId
        userLeftSession = false
        signaling.openSession(targetDeviceId: deviceId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case let .failure(msg) = result {
                    let raw = msg.localizedDescription
                    // "offline" = le peer n'a pas encore fait hello côté
                    // serveur (fenêtre courte post-pairing, sync avatar iCloud,
                    // reconnexion). Retry silencieux 1× à 2s au lieu d'un toast
                    // rouge — inutile de paniquer l'utilisateur pour un race.
                    if raw.contains("offline") {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if self.activePeerId == deviceId,
                           self.onlinePeerIds.contains(deviceId) == false
                        {
                            // Toujours offline — pas de toast alarmant, juste
                            // reset activePeerId. Le fichier passera par relay
                            // HTTPS de toute façon (marche même sans session).
                            self.activePeerId = nil
                        } else if self.activePeerId == deviceId {
                            // Le peer est réapparu online entre-temps — retry.
                            self.signaling.openSession(targetDeviceId: deviceId) { _ in }
                        }
                    } else {
                        self.toast = "Session failed: \(raw)"
                        self.activePeerId = nil
                    }
                }
            }
        }
    }

    func leaveSession() {
        userLeftSession = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        lastActivePeerId = nil
        signaling.leaveSession()
        manager.close(reason: "leave")
        activePeerId = nil
        // Reset des états incoming — sinon un vieux fichier / texte / transfer
        // en cours reste affiché à la reconnexion suivante (bug UX).
        lastIncomingFile = nil
        lastIncomingText = nil
        incomingTransfer = nil
    }

    private func scheduleAutoReconnect(after seconds: Double) {
        guard !userLeftSession,
              let peerId = lastActivePeerId,
              reconnectAttempts < maxReconnectAttempts
        else {
            reconnectAttempts = 0
            return
        }
        reconnectAttempts += 1
        toast = "Reconnecting… (\(reconnectAttempts)/\(maxReconnectAttempts))"
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard isSignalingConnected,
                  onlinePeerIds.contains(peerId),
                  !userLeftSession
            else {
                reconnectAttempts = 0
                return
            }
            openSession(with: peerId)
        }
    }

    /// Best-effort mDNS lookup for a Poof gateway on the LAN. If found and
    /// different from the current URL, swap in the discovered endpoint. Silent
    /// no-op on failure — the hardcoded/saved URL keeps working.
    private func autoDiscoverGateway() async {
        guard let endpoint = await discovery.find(timeout: 3.0),
              let url = endpoint.url else { return }
        if url.absoluteString == Self.signalingURL.absoluteString {
            return
        }
        poofLog("[Poof] discovery: gateway @ \(url.absoluteString)")
        updateSignalingURL(url)
    }

    /// Toggle Air-gap at runtime. If turning ON with a non-LAN signaling URL,
    /// disconnect and wait for LAN discovery. If turning OFF, resume normal connect.
    func applyAirGap(_ on: Bool) {
        if on, !AirGap.isLAN(Self.signalingURL) {
            signaling.leaveSession()
            manager.close(reason: "airgap")
            signaling.disconnect()
            isSignalingConnected = false
            isRTCConnected = false
            activePeerId = nil
            onlinePeerIds = []
            connectionState = "Air-gapped · LAN only"
            toast = "Air-gapped: signaling server is not on your LAN"
            Task { [weak self] in await self?.autoDiscoverGateway() }
        } else if !on, !isSignalingConnected {
            signaling.connect()
        }
    }

    func updateSignalingURL(_ url: URL) {
        if AirGap.enabled, !AirGap.isLAN(url) {
            toast = "Air-gapped: refused non-LAN signaling URL"
            return
        }
        UserDefaults.standard.set(url.absoluteString, forKey: "poof.signalingURL")
        guard started else { return }
        signaling.disconnect()
        manager.close(reason: "url-change")
        signaling = PoofSignalingClient(url: url)
        signaling.attach(manager)
        signaling.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        activePeerId = nil
        onlinePeerIds = []
        pairCode = nil
        signaling.connect()
    }

    func completeOnboarding() {
        Self.hasOnboarded = true
    }

    func enterBackground() {
        guard started else { return }
        poofLog("[Poof] app backgrounded — disconnecting signaling")
        userLeftSession = true
        reconnectTask?.cancel()
        signaling.leaveSession()
        manager.close(reason: "background")
        signaling.disconnect()
        isSignalingConnected = false
        isRTCConnected = false
        activePeerId = nil
        onlinePeerIds = []
    }

    func returnToForeground() {
        guard started else { return }
        poofLog("[Poof] app foregrounded — reconnecting signaling")
        userLeftSession = false
        signaling.connect()
        // Balayage à chaque retour au premier plan — un fichier Secure dont
        // l'expiry est atteinte pendant que l'app était en background doit
        // être supprimé avant que l'utilisateur puisse le rouvrir.
        sweepExpiredSecureFiles()
    }

    func unpair(_ deviceId: String) {
        if activePeerId == deviceId {
            leaveSession()
        }
        signaling.broadcastUnpair(deviceId)
        signaling.unsubscribe([deviceId])
        onlinePeerIds.remove(deviceId)
        peers.remove(deviceId)
    }

    func isPeerOnline(_ id: String) -> Bool {
        let target = id.lowercased()
        return onlinePeerIds.contains(where: { $0.lowercased() == target })
    }

    func pushClipboard() {
        clipboard.pushCurrent()
    }

    /// Envoie le device token APNS au serveur signaling. Appelé par l'app
    /// au launch dès que `PoofPushManager` reçoit le token de l'OS.
    /// Stocké aussi pour re-emit après chaque `hello` (car le server ignore
    /// silencieusement register-push-token tant que hello n'est pas passé).
    func registerPushToken(_ token: String) {
        pendingPushToken = token
        if isSignalingConnected {
            signaling.registerPushToken(token, platform: PoofPlatform.platform)
        }
    }

    private var pendingPushToken: String?

    /// Notify the sender that we opened the file preview — flips receipt to .seen.
    /// Enrichi optionnellement du kind (opened) et du device pour alimenter
    /// le Track côté sender. Double-envoi :
    /// 1) WebRTC direct (fast path, marche si le sender est online)
    /// 2) Push alert via signaling → APNS (fallback pour sender app-fermée)
    func markSeen(_ id: UUID, kind: TrackEvent.Kind = .opened) {
        files.markSeen(id, kind: kind, device: currentDeviceName)
        // Push fallback : le serveur route via APNS si le sender est offline.
        // Le sender déduplique côté recordTrackEvent (le premier arrive gagne).
        if let peerId = activePeerId {
            let deviceLabel = currentDeviceName
            signaling.sendPushAlert(
                toDeviceId: peerId,
                title: "File opened",
                body: "\(deviceLabel) opened your file"
            )
        }
    }

    /// Nom lisible de l'appareil ("iPhone de Uras" / "MacBook Pro d'Uras"),
    /// utilisé comme device label dans les Track events envoyés au sender.
    private var currentDeviceName: String {
        #if canImport(UIKit)
            return UIDevice.current.name
        #elseif canImport(AppKit)
            return Host.current().localizedName ?? "Mac"
        #else
            return "Device"
        #endif
    }

    private func activePeerInfo() -> (String, String) {
        guard let id = activePeerId,
              let peer = peers.peers.first(where: { $0.id == id })
        else {
            return ("", "Unknown")
        }
        return (peer.id, peer.name)
    }

    private func updateReceipt(id: UUID, state: PoofReceiptState) {
        guard let idx = sentFiles.firstIndex(where: { $0.id == id }) else { return }
        var entry = sentFiles[idx]
        // Never downgrade (seen > delivered > sent)
        let order: [PoofReceiptState] = [.sent, .delivered, .seen]
        let currentRank = order.firstIndex(of: entry.receipt) ?? 0
        let newRank = order.firstIndex(of: state) ?? 0
        guard newRank >= currentRank else { return }
        entry.receipt = state
        if state == .delivered, entry.deliveredAt == nil {
            entry.deliveredAt = Date()
        }
        if state == .seen, entry.seenAt == nil {
            entry.seenAt = Date()
        }
        sentFiles[idx] = entry
    }

    /// Push whatever is on the pasteboard (text or image). Returns a human-readable
    /// summary of what was pushed, or nil if the pasteboard was empty / unsupported.
    /// Premium+ feature — image path writes a temp PNG and sends via file transfer.
    @discardableResult
    func pushClipboardRich() -> String? {
        if let text = PoofPlatform.clipboardString, !text.isEmpty {
            clipboard.pushCurrent()
            return "Text sent"
        }
        if let image = PoofPlatform.clipboardImage,
           let png = image.poofPNGData
        {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PoofOutgoing", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let name = "clipboard-\(Int(Date().timeIntervalSince1970)).png"
            let dest = tempDir.appendingPathComponent(name)
            do {
                try png.write(to: dest)
                sendFile(at: dest, mime: "image/png")
                return "Image sent"
            } catch {
                return nil
            }
        }
        return nil
    }

    func clearHistory() {
        for entry in receivedFiles {
            try? FileManager.default.removeItem(at: entry.url)
        }
        receivedFiles = []
    }

    func sendText(_ text: String) {
        let env = PoofEnvelope(
            type: .clipboard,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: true,
            payload: ["text": text, "fp": String(text.hashValue, radix: 16)]
        )
        manager.sendEnvelope(env)
    }

    func sendFile(
        at url: URL,
        mime: String = "application/octet-stream",
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil,
        boostConfig: BoostConfig? = nil,
        studioConfig: StudioConfig? = nil,
        offlineConfig: OfflineConfig? = nil
    ) {
        // GATE PREMIUM CENTRAL — un compte Free ne peut PAS profiter des configs
        // Premium même si l'UI a été bypassée. On force nil sur chaque config
        // Premium ici (single point of enforcement, difficile à contourner).
        let isPremium = PoofPremiumStore.shared.isPremium
        let secureConfig = isPremium ? secureConfig : nil
        let trackConfig = isPremium ? trackConfig : nil
        let boostConfig = isPremium ? boostConfig : nil
        let studioConfig = isPremium ? studioConfig : nil
        let offlineConfig = isPremium ? offlineConfig : nil

        // Gate Boost — au-dessus de 500 Mo un compte Free est bloqué et voit
        // la paywall pré-scrollée sur Boost (« Sans limites, à toute vitesse »).
        if !isPremium, poofFileSize(url) > 500 * 1024 * 1024 {
            toast = "Files over 500 MB need Poof Premium"
            PoofPremiumGate.shared.present(scrollTo: .boost)
            return
        }
        // Studio actif + fichier vidéo → on encode avant l'envoi. L'encode
        // se fait dans une Task pour ne pas bloquer l'UI ; on affiche un
        // toast pendant l'opération (peut prendre plusieurs secondes).
        if let studio = studioConfig, isVideoFile(url: url, mime: mime) {
            Task { [weak self] in
                guard let self else { return }
                await MainActor.run { self.toast = "Encoding for \(studio.platform.rawValue)…" }
                do {
                    let encoded = try await PoofStudioEncoder.encode(source: url, config: studio)
                    await MainActor.run { self.toast = "Encoded, sending…" }
                    dispatchSend(
                        url: encoded, mime: "video/mp4",
                        secureConfig: secureConfig, trackConfig: trackConfig,
                        boostConfig: boostConfig, offlineConfig: offlineConfig
                    )
                } catch {
                    // Fallback silencieux : on envoie le master d'origine si
                    // l'encode a raté — l'utilisateur reçoit toujours le fichier.
                    await MainActor.run { self.toast = "Encode failed, sending master" }
                    dispatchSend(
                        url: url, mime: mime,
                        secureConfig: secureConfig, trackConfig: trackConfig,
                        boostConfig: boostConfig, offlineConfig: offlineConfig
                    )
                }
            }
            return
        }
        dispatchSend(
            url: url, mime: mime,
            secureConfig: secureConfig, trackConfig: trackConfig,
            boostConfig: boostConfig, offlineConfig: offlineConfig
        )
    }

    /// Route interne — décide entre canal Offline (MultipeerConnectivity),
    /// broadcast Boost, et envoi WebRTC standard single-peer.
    /// Priorité : Offline > Broadcast Boost > WebRTC direct.
    private func dispatchSend(
        url: URL,
        mime: String,
        secureConfig: SecureConfig?,
        trackConfig: TrackConfig?,
        boostConfig: BoostConfig?,
        offlineConfig: OfflineConfig?
    ) {
        // Offline actif → BT/Wi-Fi Direct (mode avion OK). On attend jusqu'à
        // 15s qu'un peer MC soit joignable (le browse/advertise peut prendre
        // quelques secondes à converger). Si toujours aucun peer → fail
        // explicite au lieu de fallback vers relay HTTPS qui exige internet
        // et casserait le contrat "mode avion" de la feature Offline.
        if offlineConfig != nil {
            Task { [weak self, url] in
                guard let self else { return }
                let deadline = Date().addingTimeInterval(15)
                while offline.connectedPeers.isEmpty, Date() < deadline {
                    await MainActor.run { self.toast = "Searching for nearby device…" }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                await MainActor.run {
                    if self.offline.connectedPeers.isEmpty {
                        self.toast = "No offline device found nearby"
                    } else {
                        // Broadcast à tous les devices "linked offline" actuellement
                        // connectés — l'utilisateur a coché plusieurs cibles dans
                        // le sheet, chacune reçoit sa copie chiffrée.
                        let count = self.offline.sendFileToAll(at: url, name: url.lastPathComponent)
                        self.toast = count > 1
                            ? "Sending offline to \(count) devices…"
                            : "Sending via Bluetooth/Wi-Fi Direct…"
                    }
                }
            }
            return
        }
        if boostConfig?.broadcastToAll == true {
            broadcastFile(at: url, mime: mime, secureConfig: secureConfig, trackConfig: trackConfig)
            return
        }
        // Pipeline sender : compress (Boost) → encrypt (Secure) → send.
        // L'ordre compte : le clair compresse mieux que du chiffré (aléatoire
        // par construction). Chaque étape est opt-in via son config respectif.
        // `originalName` préserve le vrai nom (photo.jpg) — les fichiers
        // temporaires transformés ont des extensions .lzfse/.enc qu'on ne
        // veut pas exposer au receiver.
        let originalName = url.lastPathComponent
        var payloadURL = url
        var didCompress = false
        if boostConfig?.compression == true {
            do {
                payloadURL = try BoostCompression.compressFile(at: payloadURL)
                didCompress = true
            } catch {
                toast = "Compression failed: \(error.localizedDescription)"
            }
        }
        if secureConfig != nil, let peerId = activePeerId {
            let key = SecureCrypto.sessionKey(
                localDeviceId: PoofDeviceIdentity.deviceId,
                peerDeviceId: peerId
            )
            do {
                payloadURL = try SecureCrypto.encryptFile(at: payloadURL, using: key)
            } catch {
                toast = "Encryption failed: \(error.localizedDescription)"
                return
            }
        }
        // ⚠️ RELAY HTTPS remplace WebRTC pour les fichiers. Contourne tous
        // les bugs SCTP/buffer/handshake du transfert P2P. Trade-off : les
        // fichiers passent par le serveur Render (mais le signaling y passait
        // déjà, donc pas de vraie perte de privacy).
        Task { [payloadURL, didCompress, weak self] in
            guard let self else { return }
            guard let targetId = activePeerId ?? lastActivePeerId else {
                await MainActor.run { self.toast = "No peer — send aborted" }
                return
            }
            let transferId = UUID()
            let fileSize = UInt64((try? FileManager.default
                    .attributesOfItem(atPath: payloadURL.path)[.size] as? Int) ?? 0)
            await MainActor.run {
                PoofLiveActivityController.shared.startSend(
                    id: transferId.uuidString, name: originalName,
                    total: fileSize, peerName: self.activePeerInfo().1
                )
                self.toast = "Uploading…"
            }
            do {
                let fileId = try await PoofRelayClient.upload(.init(
                    fileURL: payloadURL, mime: mime,
                    targetDeviceId: targetId,
                    senderDeviceId: PoofDeviceIdentity.deviceId,
                    transferId: transferId,
                    secureConfig: secureConfig, trackConfig: trackConfig,
                    compressed: didCompress, overrideName: originalName
                )) { sent, _ in
                    // Progression temps réel — pilote la Live Activity
                    // (Dynamic Island expanded + Lock Screen) avec les
                    // bytes envoyés, sans quoi la barre reste à 0% jusqu'à
                    // la fin. `updateSend` est throttled à 4 Hz côté controller.
                    Task { @MainActor in
                        PoofLiveActivityController.shared.updateSend(
                            id: transferId.uuidString, bytes: sent
                        )
                    }
                }
                poofLog("[Poof] relay upload OK — fileId=\(fileId)")
                await MainActor.run {
                    self.toast = "Sent"
                    PoofLiveActivityController.shared.endSend(id: transferId.uuidString, success: true)
                    let peerName = self.peers.peers.first(where: { $0.id == targetId })?.name ?? "Device"
                    let sent = PoofSentFile(
                        id: transferId, name: originalName, size: fileSize,
                        peerId: targetId, peerName: peerName, date: Date(),
                        receipt: .sent, deliveredAt: nil, seenAt: nil,
                        trackConfig: trackConfig
                    )
                    self.sentFiles.insert(sent, at: 0)
                    PoofBetaCounter.shared.recordSuccessfulSend()
                    self.persistLastPeerToAppGroup(deviceId: targetId, name: peerName)
                }
            } catch {
                poofLog("[Poof] relay upload FAILED — \(error.localizedDescription)")
                await MainActor.run {
                    self.toast = "Send failed: \(error.localizedDescription)"
                    PoofLiveActivityController.shared.endSend(id: transferId.uuidString, success: false)
                }
            }
        }
    }

    /// Attend que la connexion WebRTC soit prête, jusqu'au timeout. Retourne
    /// true dès que `isRTCConnected` passe à true, false si timeout dépassé.
    /// Utilisé au début de `dispatchSend` pour éviter les envois silencieux
    /// vers un canal fermé.
    private func waitForRTCReady(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRTCConnected {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return isRTCConnected
    }

    /// Détecte une vidéo — check MIME d'abord (source de vérité si spécifié),
    /// fallback sur l'extension du path si le MIME est générique.
    /// Studio ne s'active que pour les vraies vidéos, sinon on saute l'encode.
    private func isVideoFile(url: URL, mime: String) -> Bool {
        if mime.hasPrefix("video/") {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "hevc", "prores", "avi", "mkv"].contains(ext)
    }

    /// Envoi batch — itère séquentiellement sur `sendFile` avec les mêmes
    /// modifiers pour chaque fichier. Chip Boost promesse #2 "jusqu'à 1000
    /// fichiers d'un coup". Le premier fichier trop gros bloque uniquement
    /// lui-même, les autres passent (fail isolé, pas global).
    func sendFiles(
        at urls: [URL],
        mime: String = "application/octet-stream",
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil,
        boostConfig: BoostConfig? = nil,
        studioConfig: StudioConfig? = nil,
        offlineConfig: OfflineConfig? = nil
    ) {
        toast = "Sending \(urls.count) files…"
        for url in urls {
            sendFile(
                at: url, mime: mime,
                secureConfig: secureConfig, trackConfig: trackConfig,
                boostConfig: boostConfig, studioConfig: studioConfig,
                offlineConfig: offlineConfig
            )
        }
    }

    /// Taille du fichier en octets, 0 si illisible (on ne veut pas planter
    /// ce chemin — le fallback laisse l'envoi tenter sa chance).
    private func poofFileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Family-tier broadcast: send the same file to every online paired device.
    /// Opens each session sequentially — WebRTC only holds one active peer at a time.
    func broadcastFile(
        at url: URL,
        mime: String = "application/octet-stream",
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil
    ) {
        // Broadcast = feature Boost Premium. Force nil sur configs Premium
        // pour Free (double sécurité au cas où sendFile ne serait pas
        // l'entrée utilisée).
        let isPremium = PoofPremiumStore.shared.isPremium
        guard isPremium else {
            toast = "Broadcast needs Poof Premium"
            PoofPremiumGate.shared.present(scrollTo: .boost)
            return
        }
        let secureConfig = isPremium ? secureConfig : nil
        let trackConfig = isPremium ? trackConfig : nil

        let targets = peers.peers.filter { isPeerOnline($0.id) }
        guard !targets.isEmpty else {
            toast = "No family device online"
            return
        }
        toast = "Broadcasting to \(targets.count) device\(targets.count == 1 ? "" : "s")"
        Task { [weak self] in
            guard let self else { return }
            for peer in targets {
                await sendFileTo(
                    peerId: peer.id, url: url, mime: mime,
                    secureConfig: secureConfig, trackConfig: trackConfig
                )
            }
            toast = "Broadcast complete"
        }
    }

    private func sendFileTo(
        peerId: String,
        url: URL,
        mime: String,
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil
    ) async {
        openSession(with: peerId)
        let deadline = Date().addingTimeInterval(15)
        while !(isRTCConnected && activePeerId == peerId), Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard isRTCConnected, activePeerId == peerId else { return }
        try? await files.send(
            fileAt: url, mime: mime,
            secureConfig: secureConfig, trackConfig: trackConfig
        )
    }

    private func acceptReceivedFile(
        id: UUID,
        name: String,
        url: URL,
        size: UInt64,
        secureConfig: SecureConfig? = nil,
        trackConfig: TrackConfig? = nil
    ) {
        // Debug crucial : trace la taille physique du fichier au moment de
        // l'accept. Si 0 bytes ici alors que meta.size > 0 → le decrypt ou
        // les writes de chunks ont foiré, on remonte l'erreur au user.
        let physicalSize = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        poofLog(
            "[Poof] acceptReceivedFile — name=\(name) meta.size=\(size) physical=\(physicalSize) secure=\(secureConfig != nil)"
        )
        // Rejet radical : tout fichier reçu à 0 bytes (peu importe la taille
        // annoncée par le sender) est considéré comme un transfert cassé —
        // supprimé de suite pour ne JAMAIS apparaître dans Received tiles.
        if physicalSize == 0 {
            toast = "Empty file received — ask sender to resend"
            try? FileManager.default.removeItem(at: url)
            return
        }
        lastIncomingFile = url
        if secureConfig != nil {
            toast = "Secure file received: \(name)"
        } else if trackConfig != nil {
            toast = "Tracked file received: \(name)"
        } else {
            toast = "File received: \(name)"
        }
        let entry = ReceivedFile(
            id: id, name: name, url: url, size: size, date: Date(),
            secureConfig: secureConfig, trackConfig: trackConfig, openedAt: nil
        )
        receivedFiles.insert(entry, at: 0)
        if receivedFiles.count > 30 {
            receivedFiles.removeLast(receivedFiles.count - 30)
        }
        // Pic de dopamine réception : haptique + notif publique via `toast`
        // (déjà set au-dessus). Le ripple visuel côté Received est déclenché
        // par le @Published `receivedFiles.insert` que la vue observe.
        PoofHaptics.receive()
    }

    func approveKidFile() {
        guard let pending = pendingKidReview else { return }
        pendingKidReview = nil
        acceptReceivedFile(id: pending.id, name: pending.name, url: pending.url, size: pending.size)
    }

    // MARK: - Secure — enforcement helpers

    /// Marque un fichier reçu comme ouvert (première visualisation).
    /// Utilisé par les règles one-time view + expiry decay.
    func markSecureOpened(_ id: UUID) {
        guard let idx = receivedFiles.firstIndex(where: { $0.id == id }) else { return }
        var entry = receivedFiles[idx]
        entry.openedAt = Date()
        receivedFiles[idx] = entry
    }

    /// Purge définitive d'un fichier reçu — libère l'espace disque et le
    /// retire de l'historique. Appelé par la règle one-time view après la
    /// première ouverture, ou par la sweep d'expiration.
    func purgeReceivedFile(_ id: UUID) {
        guard let idx = receivedFiles.firstIndex(where: { $0.id == id }) else { return }
        let entry = receivedFiles[idx]
        try? FileManager.default.removeItem(at: entry.url)
        receivedFiles.remove(at: idx)
    }

    /// Balayage des fichiers reçus — retire ceux dont l'expiry est atteinte.
    /// Purge aussi les copies galerie (iOS) via PHPhotoLibrary, ce qui
    /// déclenche un dialog système « Supprimer ces photos ? » — Apple ne
    /// permet pas de suppression silencieuse d'assets user-owned.
    /// Le sweep se déclenche via timer 60s + returnToForeground + onAppear
    /// des sheets Received/History.
    func sweepExpiredSecureFiles() {
        let expired = receivedFiles.filter(\.isExpired)
        guard !expired.isEmpty else { return }

        let galleryIdentifiers = expired.flatMap(\.savedAssetIds)
        if !galleryIdentifiers.isEmpty {
            toast = "Purging \(galleryIdentifiers.count) gallery cop\(galleryIdentifiers.count == 1 ? "y" : "ies")…"
            PoofGalleryPurge.deleteAssets(withLocalIdentifiers: galleryIdentifiers) { [weak self] ok in
                if !ok {
                    self?.toast = "Gallery purge cancelled or denied"
                }
            }
        }
        for entry in expired {
            purgeReceivedFile(entry.id)
        }
    }

    /// Enregistre l'identifiant d'un PHAsset créé lorsque l'utilisateur a
    /// sauvegardé un fichier Secure dans sa galerie Photos. La liste sera
    /// balayée à l'expiration pour supprimer aussi la copie galerie.
    func recordSavedAsset(id: String, for fileId: UUID) {
        guard let idx = receivedFiles.firstIndex(where: { $0.id == fileId }) else { return }
        receivedFiles[idx].savedAssetIds.append(id)
    }

    // MARK: - Track — event storage + toast

    /// Enregistre un événement Track côté sender et affiche un toast
    /// in-app + une vraie notif système si le contrat local le prévoit
    /// (`notifyOnOpen`). La notif système apparaît même app en background,
    /// contrairement au toast qui ne s'affiche qu'au 1er plan.
    func recordTrackEvent(_ event: TrackEvent) {
        let sentFile = sentFiles.first(where: { $0.id == event.transferId })
        let track = sentFile?.trackConfig
        let readReceipts = track?.readReceipts == true
        let notifyOnOpen = track?.notifyOnOpen == true
        poofLog(
            "[Poof] recordTrackEvent — id=\(event.transferId) device=\(event.device ?? "?") kind=\(event.kind.rawValue) readReceipts=\(readReceipts) notifyOnOpen=\(notifyOnOpen)"
        )

        // readReceipts ON → stocke l'event pour l'historique + compteur.
        // OFF → drop l'event (Track sert juste pour customMessage/notif).
        if readReceipts {
            trackEvents[event.transferId, default: []].append(event)
        }

        // notifyOnOpen ON → toast + notif système à chaque ouverture.
        guard notifyOnOpen else { return }
        let deviceLabel = event.device ?? "device"
        let fileName = sentFile?.name ?? "your file"
        switch event.kind {
        case .opened:
            toast = "Opened by \(deviceLabel)"
            PoofTrackNotifier.fireOpened(sender: deviceLabel, fileName: fileName)
        }
        PoofHaptics.tap()
    }

    func blockKidFile() {
        guard let pending = pendingKidReview else { return }
        pendingKidReview = nil
        try? FileManager.default.removeItem(at: pending.url)
        toast = "Blocked: \(pending.name)"
    }

    /// Drains files enqueued by the Share Extension. Runs on launch and on
    /// every `poof://share` URL open. Waits (bounded) for the WebRTC channel
    /// to be up so shares taken while offline are held until reconnection.
    func drainSharedInbox() async {
        let pending = SharedStore.loadQueue()
        guard !pending.isEmpty else { return }

        let deadline = Date().addingTimeInterval(15)
        while !isRTCConnected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard isRTCConnected else {
            toast = "Shared \(pending.count) item(s) — will send when connected"
            return
        }

        for item in pending {
            guard let url = SharedStore.fileURL(for: item) else { continue }
            do {
                try await files.send(fileAt: url, mime: item.mime)
                SharedStore.remove(item.id)
            } catch {
                toast = "Share failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Event routing

    private func handle(_ event: PoofSignalingClient.Event) {
        switch event {
        case .connected:
            isSignalingConnected = true
            connectionState = "Waiting for peer…"
            sayHello()
        case let .disconnected(r):
            isSignalingConnected = false
            connectionState = "Offline (\(r))"
        case let .peerOnline(id):
            poofLog("[Poof] peer-online \(id)")
            onlinePeerIds.insert(id)
            peers.touch(id)
            if activePeerId == nil, !userLeftSession, peers.has(id) {
                openSession(with: id)
            }
        case let .peerOffline(id):
            poofLog("[Poof] peer-offline \(id)")
            onlinePeerIds.remove(id)
        case let .pairSucceeded(peer):
            peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
            signaling.subscribe([peer.deviceId])
            onlinePeerIds.insert(peer.deviceId)
            pairCode = nil
            toast = "Paired with \(peer.name)"
        case .pairExpired:
            pairCode = nil
        case let .sessionOpened(_, _, from):
            connectionState = "Session opening…"
            reconnectAttempts = 0
            if let from {
                activePeerId = from
                lastActivePeerId = from
                userLeftSession = false
            }
        case let .sessionClosed(_, r), let .peerLeft(_, r):
            connectionState = "Session closed (\(r))"
            isRTCConnected = false
            activePeerId = nil
            if shouldAutoReconnect(reason: r) {
                scheduleAutoReconnect(after: 1.5)
            }
        case let .peerUnpaired(id):
            poofLog("[Poof] peer-unpaired \(id)")
            if activePeerId == id {
                leaveSession()
            }
            onlinePeerIds.remove(id)
            peers.remove(id)
            toast = "A paired device removed you"
        case let .relayFileReady(fileId, meta):
            handleRelayFileReady(fileId: fileId, meta: meta)
        case let .accountAvatarSync(avatarBase64, displayName):
            PoofProfileImage.shared.applyRemoteSync(
                avatarBase64: avatarBase64, displayName: displayName
            )
        case let .clipboardInbound(text, senderName, clipboardId):
            handleClipboardInbound(text: text, senderName: senderName, clipboardId: clipboardId)
        case let .error(msg):
            connectionState = "Error: \(msg)"
        }
    }

    /// IDs de clipboards déjà consommés dans cette session. Évite le double
    /// affichage du toast si le serveur re-envoie le même clipboard (rare,
    /// mais peut arriver sur reconnexion socket.io avant que le fix serveur
    /// ne soit déployé, ou sur retry APNS ↔ socket.io simultané).
    private var seenClipboardIds: Set<String> = []

    /// Callback quand le serveur relaie un clipboard entrant. On écrit dans
    /// le pasteboard système (marche silent sur macOS + iOS foreground). Sur
    /// iOS background/tuée, c'est la notif APNS avec bouton « 📋 Coller »
    /// (côté AppDelegate) qui prend le relai — cette closure ne s'exécute
    /// pas dans ce cas car l'app n'est pas active.
    private func handleClipboardInbound(text: String, senderName: String, clipboardId: String) {
        guard !seenClipboardIds.contains(clipboardId) else { return }
        seenClipboardIds.insert(clipboardId)
        if seenClipboardIds.count > 100 {
            // Cap mémoire — les IDs sont éphémères, 100 = large marge.
            seenClipboardIds.removeFirst()
        }
        PoofPlatform.setClipboardString(text)
        // Persiste dans le store partagé pour que le menu bar Mac / Control
        // Center widget iOS puisse re-coller à la demande de l'user, même
        // après un lock/relaunch de l'app.
        PoofClipboardStore.shared.record(text: text, senderName: senderName)
        let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
        toast = "📋 Pasted from \(senderName) — \"\(preview)\""
    }

    /// Écrit l'identité self dans le App Group UserDefaults `group.com.poofapp.shared`
    /// — utilisé par les App Intents (Action Button / Siri / widget) pour
    /// signer les POST au serveur relay sans avoir besoin de PoofSession.
    private func persistSelfIdentityToAppGroup() {
        guard let d = UserDefaults(suiteName: "group.com.poofapp.shared") else { return }
        d.set(PoofDeviceIdentity.deviceId, forKey: "poof.selfDeviceId")
        d.set(PoofDeviceIdentity.name, forKey: "poof.selfDeviceName")
        d.set(Self.signalingURL.absoluteString, forKey: "poof.signalingURL")
    }

    /// Persiste le dernier peer utilisé pour envoyer — l'App Intent
    /// « Envoyer clipboard avec Poof » l'utilise comme cible par défaut.
    private func persistLastPeerToAppGroup(deviceId: String, name: String) {
        guard let d = UserDefaults(suiteName: "group.com.poofapp.shared") else { return }
        d.set(deviceId, forKey: "poof.lastPeerDeviceId")
        d.set(name, forKey: "poof.lastPeerName")
    }

    /// Envoie un texte au device paired via le relay HTTPS. Marche même si
    /// le receiver n'a pas l'app ouverte (APNS + queue serveur TTL 1h).
    /// C'est le pattern à utiliser au lieu de `clipboard.pushCurrent()` qui
    /// passe par WebRTC direct (échoue si receiver offline).
    func sendClipboardViaRelay(text: String) {
        guard !text.isEmpty else { return }
        guard let targetId = activePeerId ?? lastActivePeerId ?? peers.peers.first?.id else {
            toast = "No paired device"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await PoofRelayClient.pushClipboard(
                    text: text,
                    targetDeviceId: targetId,
                    senderName: PoofDeviceIdentity.name
                )
                await MainActor.run { self.toast = "📋 Clipboard sent" }
            } catch {
                await MainActor.run { self.toast = "Clipboard: \(error.localizedDescription)" }
            }
        }
    }

    /// Callback quand le serveur signale qu'un fichier relay est dispo pour
    /// nous. Download HTTPS + pipeline decrypt/decompress + acceptReceivedFile.
    private func handleRelayFileReady(fileId: String, meta: [String: Any]) {
        Task { @MainActor in
            let name = (meta["name"] as? String) ?? "file"
            let mime = (meta["mime"] as? String) ?? "application/octet-stream"
            let size = UInt64((meta["size"] as? Int) ?? 0)
            let compressed = (meta["compressed"] as? Bool) ?? false
            let transferIdStr = (meta["transferId"] as? String) ?? UUID().uuidString
            let transferId = UUID(uuidString: transferIdStr) ?? UUID()
            let senderId = (meta["senderDeviceId"] as? String) ?? ""

            var secureCfg: SecureConfig?
            if let raw = meta["secureConfig"] as? [String: Any],
               let json = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode(SecureConfig.self, from: json)
            {
                secureCfg = decoded
            }
            var trackCfg: TrackConfig?
            if let raw = meta["trackConfig"] as? [String: Any],
               let json = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode(TrackConfig.self, from: json)
            {
                trackCfg = decoded
            }

            self.toast = "Downloading…"
            self.incomingTransfer = TransferProgress(id: transferId, name: name, total: size, received: 0)
            PoofLiveActivityController.shared.startReceive(
                id: transferId.uuidString, name: name, total: size, peerName: self.activePeerInfo().1
            )

            do {
                let (url, _) = try await PoofRelayClient.download(fileId: fileId)
                poofLog("[Poof] relay download OK — \(url.path)")

                // Pipeline decrypt (Secure) → decompress (Boost) — même
                // ordre que WebRTC.
                var finalURL = url
                if secureCfg != nil {
                    let key = SecureCrypto.sessionKey(
                        localDeviceId: PoofDeviceIdentity.deviceId,
                        peerDeviceId: senderId
                    )
                    do {
                        try SecureCrypto.decryptInPlace(finalURL, using: key)
                    } catch {
                        self.toast = "Decryption failed"
                        try? FileManager.default.removeItem(at: finalURL)
                        return
                    }
                }
                if compressed {
                    do {
                        try BoostCompression.decompressInPlace(finalURL)
                    } catch {
                        self.toast = "Decompression failed"
                        try? FileManager.default.removeItem(at: finalURL)
                        return
                    }
                }
                let finalSize = UInt64((try? FileManager.default
                        .attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0)
                self.incomingTransfer = nil
                PoofLiveActivityController.shared.endReceive(id: transferId.uuidString, success: true)
                self.acceptReceivedFile(
                    id: transferId, name: name, url: finalURL, size: finalSize,
                    secureConfig: secureCfg, trackConfig: trackCfg
                )
            } catch {
                poofLog("[Poof] relay download FAILED — \(error.localizedDescription)")
                self.toast = "Download failed: \(error.localizedDescription)"
                self.incomingTransfer = nil
                PoofLiveActivityController.shared.endReceive(id: transferId.uuidString, success: false)
            }
        }
    }

    private func handle(state: PoofWebRTCManager.State) {
        switch state {
        case .idle:
            connectionState = "Idle"
        case .connecting:
            connectionState = "Connecting…"
        case .connected:
            connectionState = "Online"
            isRTCConnected = true
            reconnectAttempts = 0
            // Wake up any file sends that were paused waiting for the
            // channel — receiver will hand back its expected chunk index.
            files.resumeAllActiveSends()
            // Vide la file d'attente clipboard qui n'a pas pu partir pendant
            // l'offline (control channel fermé). Sans ça les copies faites
            // avant la reconnexion étaient perdues.
            clipboard.flushPending()
        case let .closed(reason):
            connectionState = "Offline (\(reason))"
            isRTCConnected = false
            if shouldAutoReconnect(reason: reason) {
                scheduleAutoReconnect(after: 1.5 * Double(max(reconnectAttempts, 1)))
            }
        }
    }

    private func shouldAutoReconnect(reason: String) -> Bool {
        if userLeftSession {
            return false
        }
        let transient = ["ice-failed", "ice-disconnected", "peer-left", "peer-disconnected", "peer-closed"]
        return transient.contains(where: { reason.contains($0) })
    }

    private func sayHello() {
        let known = peers.ids
        let appleUserId = PoofProfileImage.shared.appleUserId
        poofLog("[Poof] hello knownPeerIds=\(known) deviceId=\(PoofDeviceIdentity.deviceId)")
        signaling.hello(
            deviceId: PoofDeviceIdentity.deviceId,
            name: PoofDeviceIdentity.name,
            platform: PoofDeviceIdentity.platform,
            knownPeerIds: known,
            appleUserId: appleUserId
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(onlinePeers):
                    poofLog("[Poof] hello ok onlinePeers=\(onlinePeers.map(\.deviceId))")
                    self.onlinePeerIds = Set(onlinePeers.map(\.deviceId))
                    for peer in onlinePeers {
                        self.peers.upsert(deviceId: peer.deviceId, name: peer.name, platform: peer.platform)
                    }
                    if let token = self.pendingPushToken {
                        poofLog("[Poof] re-emit push token after hello")
                        self.signaling.registerPushToken(token, platform: PoofPlatform.platform)
                    }
                    // Push notre avatar iCloud local aux autres devices du même
                    // compte — le serveur relaie automatiquement à tous les
                    // sockets partageant le même appleUserId.
                    self.pushLocalAvatarIfPossible()
                case let .failure(err):
                    poofLog("[Poof] hello FAILED \(err.localizedDescription)")
                }
                let knownIds = self.peers.ids
                if !knownIds.isEmpty {
                    poofLog("[Poof] subscribing to \(knownIds)")
                    self.signaling.subscribe(knownIds)
                }
                self.maybeAutoConnect()
            }
        }
    }

    /// Envoie l'avatar + displayName local au serveur si l'utilisateur est
    /// signé (Sign in with Apple présent) et qu'on a une image. Appelé après
    /// hello succès et à chaque mutation locale (fetch Me Card, PhotosPicker).
    func pushLocalAvatarIfPossible() {
        let profile = PoofProfileImage.shared
        guard let appleUserId = profile.appleUserId else { return }
        let name = profile.displayName.isEmpty ? nil : profile.displayName
        let avatarBase64 = profile.image?.compressedJPEGBase64(maxBytes: 400_000)
        signaling.pushAccountAvatar(
            appleUserId: appleUserId,
            avatarBase64: avatarBase64,
            displayName: name
        )
    }

    private func maybeAutoConnect() {
        guard activePeerId == nil, !userLeftSession else { return }
        // Prefer known-online peers first
        if let peer = peers.peers
            .sorted(by: { $0.lastSeenAt > $1.lastSeenAt })
            .first(where: { onlinePeerIds.contains($0.id) })
        {
            openSession(with: peer.id)
            return
        }
        // Fallback: probe most-recent paired peer even if server didn't
        // report them online — server may not implement peer-online events.
        if let peer = peers.peers.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first {
            probeAndOpen(peerId: peer.id)
        }
    }

    private func probeAndOpen(peerId: String) {
        poofLog("[Poof] probing paired peer \(peerId)")
        activePeerId = peerId
        lastActivePeerId = peerId
        userLeftSession = false
        signaling.openSession(targetDeviceId: peerId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    poofLog("[Poof] probe succeeded, peer is online")
                    self.onlinePeerIds.insert(peerId)
                case let .failure(err):
                    poofLog("[Poof] probe failed \(err.localizedDescription)")
                    self.activePeerId = nil
                }
            }
        }
    }
}
