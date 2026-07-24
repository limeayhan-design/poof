import Foundation
@preconcurrency import WebRTC

// Core P2P engine. Two data channels:
//   • control — unordered, maxRetransmits:0. Carries envelopes.
//   • bulk    — ordered, reliable. Carries binary file frames.

nonisolated final class PoofWebRTCManager: NSObject, @unchecked Sendable {
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

    private let iceServers: [RTCIceServer]
    private let queue = DispatchQueue(label: "poof.webrtc", qos: .userInitiated)

    init(iceServers: [String] = ["stun:stun.l.google.com:19302"]) {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        self.iceServers = [RTCIceServer(urlStrings: iceServers)]
        super.init()
    }

    func start(asInitiator initiator: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.state = .connecting

            let cfg = RTCConfiguration()
            cfg.iceServers = self.iceServers
            cfg.sdpSemantics = .unifiedPlan
            cfg.bundlePolicy = .maxBundle
            cfg.rtcpMuxPolicy = .require

            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            self.peer = self.factory.peerConnection(with: cfg, constraints: constraints, delegate: self)

            if initiator {
                self.control = self.peer?.dataChannel(forLabel: "control", configuration: Self.controlConfig())
                self.bulk = self.peer?.dataChannel(forLabel: "bulk", configuration: Self.bulkConfig())
                self.control?.delegate = self
                self.bulk?.delegate = self
                self.createOffer()
            }
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
            if error == nil, sdp.type == .offer { self?.createAnswer(completion: completion); return }
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
            let buffer = RTCDataBuffer(data: try env.encode(), isBinary: false)
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

    var bulkBufferedAmount: UInt64 { bulk?.bufferedAmount ?? 0 }
    var isControlOpen: Bool { control?.readyState == .open }
    var isBulkOpen: Bool { bulk?.readyState == .open }

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
            self.peer?.setLocalDescription(sdp) { _ in self.onLocalDescription?(sdp) }
        }
    }

    private func createAnswer(completion: @escaping (Error?) -> Void) {
        let c = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peer?.answer(for: c) { [weak self] sdp, error in
            guard let self, let sdp else { completion(error); return }
            self.peer?.setLocalDescription(sdp) { err in
                if err == nil { self.onLocalDescription?(sdp) }
                completion(err)
            }
        }
    }
}

extension PoofWebRTCManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        queue.async { [weak self] in
            guard let self else { return }
            switch newState {
            case .connected, .completed: self.state = .connected
            case .failed:                self.state = .closed(reason: "ice-failed")
            case .disconnected:          self.state = .closed(reason: "ice-disconnected")
            default: break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onLocalCandidate?(candidate)
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        queue.async { [weak self] in
            guard let self else { return }
            if dataChannel.label == "control" { self.control = dataChannel }
            if dataChannel.label == "bulk"    { self.bulk    = dataChannel }
            dataChannel.delegate = self
        }
    }
}

extension PoofWebRTCManager: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if dataChannel.label == "bulk", buffer.isBinary {
            if let decoded = try? PoofFrame.decode(buffer.data) { onBulkFrame?(decoded) }
            return
        }
        if dataChannel.label == "control" {
            if let env = try? PoofEnvelope.decode(buffer.data) { onEnvelope?(env) }
        }
    }
}
