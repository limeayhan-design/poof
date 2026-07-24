import Foundation
import Network

// Zero-config LAN gateway discovery.
// Browses for `_poof._tcp` mDNS services published by the signaling gateway
// (see Poof/server.js). On first hit, resolves it to `http://IP:port`.
//
// Failure mode: if no gateway responds within `timeout`, we surface `nil` so
// PoofSession falls back to whatever URL is in UserDefaults or the hardcoded
// default. Discovery is best-effort — never a hard requirement.

final class PoofDiscovery {

    struct Endpoint: Equatable {
        let host: String   // IPv4 literal or hostname
        let port: UInt16
        var url: URL? { URL(string: "http://\(host):\(port)") }
    }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "poof.discovery", qos: .userInitiated)

    // Runs a bounded browse. Returns the first resolved endpoint or nil.
    func find(timeout: TimeInterval = 3.0) async -> Endpoint? {
        await withCheckedContinuation { cont in
            var resumed = false
            let finish: (Endpoint?) -> Void = { [weak self] ep in
                guard !resumed else { return }
                resumed = true
                self?.stop()
                cont.resume(returning: ep)
            }

            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: "_poof._tcp", domain: nil), using: params)
            self.browser = browser

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self, let first = results.first else { return }
                self.resolve(first.endpoint, on: self.queue) { endpoint in
                    finish(endpoint)
                }
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    // NWBrowser gives us a service endpoint; opening a connection triggers
    // resolution to IP:port. We tear down as soon as we get the resolved
    // path — we never actually need the socket.
    private func resolve(_ endpoint: NWEndpoint, on queue: DispatchQueue, completion: @escaping (Endpoint?) -> Void) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let resolved = conn.currentPath?.remoteEndpoint ?? endpoint
                completion(Self.extract(from: resolved))
                self?.connection?.cancel()
                self?.connection = nil
            case .failed, .cancelled:
                completion(nil)
                self?.connection = nil
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private static func extract(from endpoint: NWEndpoint) -> Endpoint? {
        switch endpoint {
        case .hostPort(let host, let port):
            let raw: String
            switch host {
            case .name(let n, _):     raw = n
            case .ipv4(let addr):     raw = "\(addr)"
            case .ipv6(let addr):     raw = "[\(addr)]"
            @unknown default:         raw = "\(host)"
            }
            // NWIPv4Address prints as "1.2.3.4%en0" — strip the interface.
            let clean = raw.split(separator: "%").first.map(String.init) ?? raw
            return Endpoint(host: clean, port: port.rawValue)
        default:
            return nil
        }
    }
}
