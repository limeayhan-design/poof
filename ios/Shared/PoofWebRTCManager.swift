import Foundation
@preconcurrency import WebRTC

// Core P2P engine. Two data channels:
//   • control — unordered, maxRetransmits:0. Carries envelopes.
//   • bulk    — ordered, reliable. Carries binary file frames.

final nonisolated class PoofWebRTCManager: NSObject, @unchecked Sendable {
    // Runs off the main actor. All internal state guarded by `queue`.
    // Consumers must dispatch UI updates themselves.

    enum State { case idle, connecting, connected, closed(reason: String) }

    var onState: ((State) -> Void)?
    var onEnvelope: ((PoofEnvelope) -> Void)?
    var onBulkFrame: ((PoofFrame.Decoded) -> Void)?
    var onLocalDescription: ((RTCSessionDescription) -> Void)?
    var onLocalCandidate: ((RTCIceCandidate) -> Void)?

    private(set) var state: State = .idle {
        didSet { onState?(state) }
    }

    private let factory: RTCPeerConnectionFactory
    private var peer: RTCPeerConnection?
    private var control: RTCDataChannel?
    private var bulk: RTCDataChannel?
    /// Retenu depuis `start(asInitiator:)` — nécessaire pour savoir qui doit
    /// déclencher l'ICE restart en cas de disconnect (seul l'offerer peut le
    /// faire, sinon on double-négocie).
    private var isInitiator: Bool = false
    private var iceRestartWorkItem: DispatchWorkItem?

    // STUN gets applied only for Premium tiers. Free is intentionally LAN-only,
    // matching the paywall promise "Without Premium, Poof only works on your Wi-Fi".
    private let premiumIceServers: [RTCIceServer]
    private let queue = DispatchQueue(label: "poof.webrtc", qos: .userInitiated)

    init(iceServers: [String] = ["stun:stun.l.google.com:19302"]) {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        premiumIceServers = [RTCIceServer(urlStrings: iceServers)]
        super.init()
    }

    func start(asInitiator initiator: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            state = .connecting
            isInitiator = initiator

            let cfg = RTCConfiguration()
            // Free tier = no STUN → LAN-only. Premium = full STUN → works across networks.
            cfg.iceServers = PoofTier.current.isPremium ? premiumIceServers : []
            cfg.sdpSemantics = .unifiedPlan
            cfg.bundlePolicy = .maxBundle
            cfg.rtcpMuxPolicy = .require

            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            peer = factory.peerConnection(with: cfg, constraints: constraints, delegate: self)

            if initiator {
                control = peer?.dataChannel(forLabel: "control", configuration: Self.controlConfig())
                bulk = peer?.dataChannel(forLabel: "bulk", configuration: Self.bulkConfig())
                control?.delegate = self
                bulk?.delegate = self
                createOffer()
            }
        }
    }

    /// Recréé un offer avec `IceRestart: true` — utilisé quand la connexion
    /// tombe en `.disconnected` sans revenir seule. Le peer distant reçoit la
    /// nouvelle SDP et repart sur un nouveau candidate pool.
    private func triggerIceRestart() {
        guard isInitiator, let peer else { return }
        let c = RTCMediaConstraints(
            mandatoryConstraints: ["IceRestart": "true"],
            optionalConstraints: nil
        )
        peer.offer(for: c) { [weak self] sdp, _ in
            guard let self, let sdp else { return }
            peer.setLocalDescription(sdp) { _ in self.onLocalDescription?(sdp) }
        }
    }

    func close(reason: String = "manual") {
        queue.async { [weak self] in
            self?.control?.close()
            self?.bulk?.close()
            self?.peer?.close()
            self?.control = nil
            self?.bulk = nil
            self?.peer = nil
            self?.state = .closed(reason: reason)
        }
    }

    func handleRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        peer?.setRemoteDescription(sdp) { [weak self] error in
            if error == nil, sdp.type == .offer {
                self?.createAnswer(completion: completion)
                return
            }
            completion(error)
        }
    }

    func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        peer?.add(candidate, completionHandler: { _ in })
    }

    @discardableResult
    func sendEnvelope(_ env: PoofEnvelope) -> Bool {
        guard let channel = control, channel.readyState == .open else { return false }
        do {
            let buffer = try RTCDataBuffer(data: env.encode(), isBinary: false)
            return channel.sendData(buffer)
        } catch {
            return false
        }
    }

    @discardableResult
    func sendBulk(_ frame: Data) -> Bool {
        guard let channel = bulk, channel.readyState == .open else { return false }
        let buffer = RTCDataBuffer(data: frame, isBinary: true)
        return channel.sendData(buffer)
    }

    var bulkBufferedAmount: UInt64 {
        bulk?.bufferedAmount ?? 0
    }

    var isControlOpen: Bool {
        control?.readyState == .open
    }

    var isBulkOpen: Bool {
        bulk?.readyState == .open
    }

    private static func controlConfig() -> RTCDataChannelConfiguration {
        let c = RTCDataChannelConfiguration()
        c.isOrdered = false
        c.maxRetransmits = 0
        c.channelId = 1
        return c
    }

    private static func bulkConfig() -> RTCDataChannelConfiguration {
        let c = RTCDataChannelConfiguration()
        c.isOrdered = true
        c.channelId = 2
        return c
    }

    private func createOffer() {
        let c = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peer?.offer(for: c) { [weak self] sdp, _ in
            guard let self, let sdp else { return }
            peer?.setLocalDescription(sdp) { _ in self.onLocalDescription?(sdp) }
        }
    }

    private func createAnswer(completion: @escaping (Error?) -> Void) {
        let c = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peer?.answer(for: c) { [weak self] sdp, error in
            guard let self, let sdp else { completion(error)
                return
            }
            peer?.setLocalDescription(sdp) { err in
                if err == nil {
                    self.onLocalDescription?(sdp)
                }
                completion(err)
            }
        }
    }
}

extension PoofWebRTCManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        queue.async { [weak self] in
            guard let self else { return }
            switch newState {
            case .connected, .completed:
                state = .connected
                iceRestartWorkItem?.cancel()
                iceRestartWorkItem = nil
            case .failed:
                state = .closed(reason: "ice-failed")
                iceRestartWorkItem?.cancel()
                iceRestartWorkItem = nil
            case .disconnected:
                // Ne pas fermer la session : `.disconnected` est souvent
                // transitoire (WebRTC re-tente seul). On garde `state` inchangé
                // et on schedule un ICE restart dans 5s si toujours down.
                iceRestartWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if peer?.iceConnectionState == .disconnected {
                        triggerIceRestart()
                    }
                }
                iceRestartWorkItem = work
                queue.asyncAfter(deadline: .now() + 5, execute: work)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onLocalCandidate?(candidate)
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        queue.async { [weak self] in
            guard let self else { return }
            if dataChannel.label == "control" {
                control = dataChannel
            }
            if dataChannel.label == "bulk" {
                bulk = dataChannel
            }
            dataChannel.delegate = self
        }
    }
}

extension PoofWebRTCManager: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_: RTCDataChannel) {}

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if dataChannel.label == "bulk", buffer.isBinary {
            if let decoded = try? PoofFrame.decode(buffer.data) {
                onBulkFrame?(decoded)
            }
            return
        }
        if dataChannel.label == "control" {
            if let env = try? PoofEnvelope.decode(buffer.data) {
                onEnvelope?(env)
            }
        }
    }
}
