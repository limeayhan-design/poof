import Foundation
import SocketIO
import WebRTC

// Swift mirror of pc/src/signaling-client.js (multi-device protocol).
// Flow:
//   1. connect() → wait for .connected
//   2. hello(deviceId, name, platform, knownPeerIds:) → returns online peers among known
//   3. Either pairAdvertise() → code (show QR)  OR  pairConsume(code) → peer
//   4. openSession(targetDeviceId) → becomes offerer, WebRTC starts

enum PoofSignalingError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(m): m }
    }
}

final class PoofSignalingClient {
    struct Peer {
        let deviceId: String
        let name: String
        let platform: String
    }

    enum Event {
        case connected
        case disconnected(reason: String)
        case peerOnline(deviceId: String)
        case peerOffline(deviceId: String)
        case pairSucceeded(peer: Peer)
        case pairExpired(code: String)
        case sessionOpened(sessionId: String, initiator: Bool, from: String?)
        case sessionClosed(sessionId: String, reason: String)
        case peerLeft(sessionId: String, reason: String)
        case peerUnpaired(deviceId: String)
        case relayFileReady(fileId: String, meta: [String: Any])
        case accountAvatarSync(avatarBase64: String?, displayName: String?)
        case clipboardInbound(text: String, senderName: String, clipboardId: String)
        case error(String)
    }

    var onEvent: ((Event) -> Void)?
    private(set) var sessionId: String?
    private var startedSessionId: String?

    private weak var manager: PoofWebRTCManager?
    private let socketManager: SocketManager
    private let socket: SocketIOClient

    init(url: URL) {
        poofLog("[Poof] Signaling init → \(url.absoluteString)")
        socketManager = SocketManager(
            socketURL: url,
            config: [
                .log(true),
                .compress,
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(1)
            ]
        )
        socket = socketManager.defaultSocket
        wire()
    }

    // MARK: Public API

    func attach(_ manager: PoofWebRTCManager) {
        self.manager = manager

        manager.onLocalDescription = { [weak self] sdp in
            let event = sdp.type == .offer ? "sdp-offer" : "sdp-answer"
            self?.socket.emit(event, [
                "sdp": [
                    "type": sdp.type == .offer ? "offer" : "answer",
                    "sdp": sdp.sdp
                ]
            ])
        }

        manager.onLocalCandidate = { [weak self] candidate in
            self?.socket.emit("ice-candidate", [
                "candidate": [
                    "candidate": candidate.sdp,
                    "sdpMid": candidate.sdpMid ?? "",
                    "sdpMLineIndex": Int(candidate.sdpMLineIndex)
                ]
            ])
        }
    }

    func connect() {
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    // MARK: Identity + presence

    func hello(
        deviceId: String,
        name: String,
        platform: String,
        knownPeerIds: [String],
        appleUserId: String? = nil,
        completion: @escaping (Result<[Peer], PoofSignalingError>) -> Void
    ) {
        var payload: [String: Any] = [
            "deviceId": deviceId,
            "name": name,
            "platform": platform,
            "knownPeerIds": knownPeerIds
        ]
        if let appleUserId, !appleUserId.isEmpty {
            payload["appleUserId"] = appleUserId
        }
        socket.emitWithAck("hello", payload).timingOut(after: 15) { response in
            poofLog("[Poof] hello raw response=\(response)")
            guard let dict = response.first as? [String: Any] else { completion(.failure(.message("no-response")))
                return
            }
            if (dict["ok"] as? Bool) == true {
                let raw = (dict["onlinePeers"] as? [[String: Any]]) ?? []
                let peers = raw.compactMap(Self.parsePeer)
                completion(.success(peers))
            } else {
                completion(.failure(.message((dict["error"] as? String) ?? "hello-failed")))
            }
        }
    }

    func subscribe(_ deviceIds: [String]) {
        socket.emit("subscribe", ["deviceIds": deviceIds])
    }

    func unsubscribe(_ deviceIds: [String]) {
        socket.emit("unsubscribe", ["deviceIds": deviceIds])
    }

    func broadcastUnpair(_ deviceId: String) {
        socket.emit("unpair", ["deviceId": deviceId])
    }

    // MARK: Pairing

    func pairAdvertise(completion: @escaping (Result<String, PoofSignalingError>) -> Void) {
        socket.emitWithAck("pair-advertise", []).timingOut(after: 15) { response in
            guard let dict = response.first as? [String: Any] else { completion(.failure(.message("no-response")))
                return
            }
            if (dict["ok"] as? Bool) == true, let code = dict["code"] as? String {
                completion(.success(code))
            } else {
                completion(.failure(.message((dict["error"] as? String) ?? "advertise-failed")))
            }
        }
    }

    func pairCancel() {
        socket.emit("pair-cancel")
    }

    func pairConsume(code: String, completion: @escaping (Result<Peer, PoofSignalingError>) -> Void) {
        let normalized = code.uppercased()
        socket.emitWithAck("pair-consume", ["code": normalized]).timingOut(after: 15) { response in
            guard let dict = response.first as? [String: Any] else { completion(.failure(.message("no-response")))
                return
            }
            if (dict["ok"] as? Bool) == true, let peerDict = dict["peer"] as? [String: Any],
               let peer = Self.parsePeer(peerDict)
            {
                completion(.success(peer))
            } else {
                completion(.failure(.message((dict["error"] as? String) ?? "consume-failed")))
            }
        }
    }

    // MARK: Session

    func openSession(targetDeviceId: String, completion: @escaping (Result<String, PoofSignalingError>) -> Void) {
        socket.emitWithAck("session-open", ["targetDeviceId": targetDeviceId])
            .timingOut(after: 15) { [weak self] response in
                guard let self,
                      let dict = response.first as? [String: Any]
                else { completion(.failure(.message("no-response")))
                    return
                }
                if (dict["ok"] as? Bool) == true, let sid = dict["sessionId"] as? String {
                    sessionId = sid
                    startOnce(sid: sid, initiator: true)
                    completion(.success(sid))
                } else {
                    completion(.failure(.message((dict["error"] as? String) ?? "session-open-failed")))
                }
            }
    }

    func leaveSession() {
        socket.emit("session-leave")
        sessionId = nil
        startedSessionId = nil
    }

    // MARK: Push notifications (APNS relay via serveur)

    /// Envoie le device token APNS au serveur signaling. Le serveur le
    /// mappe au deviceId courant et l'utilisera pour relayer les push
    /// quand un event doit remonter au sender offline.
    func registerPushToken(_ token: String, platform: String) {
        poofLog("[Poof] Signaling → register-push-token (\(platform))")
        socket.emit("register-push-token", [
            "token": token,
            "platform": platform
        ])
    }

    /// Demande au serveur d'envoyer une push APNS à un peer distant.
    /// Utilisé par le receiver quand il ouvre un fichier Track pour
    /// notifier le sender même s'il est app-fermée. Le serveur route
    /// via le token précédemment registered.
    func sendPushAlert(toDeviceId: String, title: String, body: String) {
        poofLog("[Poof] Signaling → push-alert → \(toDeviceId)")
        socket.emit("push-alert", [
            "toDeviceId": toDeviceId,
            "title": title,
            "body": body
        ])
    }

    /// Pousse l'avatar + displayName du compte iCloud (identifié par
    /// `appleUserId`) au serveur. Le serveur broadcast à tous les autres
    /// sockets connectés avec le même `appleUserId` → sync cross-device
    /// automatique (iPhone ↔ Mac ↔ iPad d'un même user).
    func pushAccountAvatar(appleUserId: String, avatarBase64: String?, displayName: String?) {
        guard !appleUserId.isEmpty else { return }
        var payload: [String: Any] = ["appleUserId": appleUserId]
        if let avatarBase64 {
            payload["avatar"] = avatarBase64
        }
        if let displayName {
            payload["displayName"] = displayName
        }
        poofLog("[Poof] Signaling → account-avatar-push (bytes=\(avatarBase64?.count ?? 0))")
        socket.emit("account-avatar-push", payload)
    }

    private func startOnce(sid: String, initiator: Bool) {
        guard startedSessionId != sid else { return }
        startedSessionId = sid
        manager?.start(asInitiator: initiator)
    }

    // MARK: Internal

    private nonisolated static func parsePeer(_ dict: [String: Any]) -> Peer? {
        guard let id = dict["deviceId"] as? String else { return nil }
        return Peer(
            deviceId: id,
            name: (dict["name"] as? String) ?? "Unknown",
            platform: (dict["platform"] as? String) ?? "unknown"
        )
    }

    private func wire() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in self?.onEvent?(.connected) }
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            self?.onEvent?(.disconnected(reason: (data.first as? String) ?? "unknown"))
        }

        socket.on("peer-online") { [weak self] data, _ in
            guard let id = (data.first as? [String: Any])?["deviceId"] as? String else { return }
            self?.onEvent?(.peerOnline(deviceId: id))
        }
        socket.on("peer-offline") { [weak self] data, _ in
            guard let id = (data.first as? [String: Any])?["deviceId"] as? String else { return }
            self?.onEvent?(.peerOffline(deviceId: id))
        }
        socket.on("peer-unpaired") { [weak self] data, _ in
            guard let id = (data.first as? [String: Any])?["deviceId"] as? String else { return }
            self?.onEvent?(.peerUnpaired(deviceId: id))
        }

        socket.on("pair-succeeded") { [weak self] data, _ in
            guard let peerDict = (data.first as? [String: Any])?["peer"] as? [String: Any],
                  let peer = Self.parsePeer(peerDict) else { return }
            self?.onEvent?(.pairSucceeded(peer: peer))
        }
        socket.on("pair-expired") { [weak self] data, _ in
            let code = ((data.first as? [String: Any])?["code"] as? String) ?? ""
            self?.onEvent?(.pairExpired(code: code))
        }

        socket.on("session-opened") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let sid = dict["sessionId"] as? String else { return }
            let initiator = (dict["initiator"] as? Bool) ?? false
            let from = dict["from"] as? String
            sessionId = sid
            startOnce(sid: sid, initiator: initiator)
            onEvent?(.sessionOpened(sessionId: sid, initiator: initiator, from: from))
        }
        socket.on("session-closed") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let sid = (dict["sessionId"] as? String) ?? ""
            let reason = (dict["reason"] as? String) ?? "unknown"
            self?.sessionId = nil
            self?.startedSessionId = nil
            self?.onEvent?(.sessionClosed(sessionId: sid, reason: reason))
        }
        socket.on("peer-left") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let sid = (dict["sessionId"] as? String) ?? ""
            let reason = (dict["reason"] as? String) ?? "unknown"
            self?.startedSessionId = nil
            self?.onEvent?(.peerLeft(sessionId: sid, reason: reason))
        }
        socket.on("relay-file-ready") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let fileId = dict["fileId"] as? String,
                  let meta = dict["meta"] as? [String: Any] else { return }
            self?.onEvent?(.relayFileReady(fileId: fileId, meta: meta))
        }
        socket.on("account-avatar-sync") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let avatar = dict["avatar"] as? String
            let name = dict["displayName"] as? String
            self?.onEvent?(.accountAvatarSync(avatarBase64: avatar, displayName: name))
        }
        socket.on("clipboard-inbound") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let text = dict["text"] as? String, !text.isEmpty else { return }
            let sender = (dict["senderName"] as? String) ?? "Device"
            let cid = (dict["id"] as? String) ?? UUID().uuidString
            self?.onEvent?(.clipboardInbound(text: text, senderName: sender, clipboardId: cid))
        }

        socket.on("sdp-offer") { [weak self] data, _ in self?.receiveDescription(data.first, type: .offer) }
        socket.on("sdp-answer") { [weak self] data, _ in self?.receiveDescription(data.first, type: .answer) }
        socket.on("ice-candidate") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let cand = dict["candidate"] as? [String: Any],
                  let sdp = cand["candidate"] as? String else { return }
            let ice = RTCIceCandidate(
                sdp: sdp,
                sdpMLineIndex: Int32((cand["sdpMLineIndex"] as? Int) ?? 0),
                sdpMid: cand["sdpMid"] as? String
            )
            self?.manager?.addRemoteCandidate(ice)
        }
    }

    private func receiveDescription(_ raw: Any?, type: RTCSdpType) {
        guard let dict = raw as? [String: Any],
              let sdpDict = dict["sdp"] as? [String: Any],
              let sdp = sdpDict["sdp"] as? String else { return }
        let desc = RTCSessionDescription(type: type, sdp: sdp)
        manager?.handleRemoteDescription(desc) { _ in }
    }
}
