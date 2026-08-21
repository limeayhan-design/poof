import Foundation

// Devium tier — Air-gapped mode.
// When on, Poof refuses any signaling URL that isn't on your LAN.
// Blocks public internet servers, allows RFC1918 + .local (mDNS).

enum AirGap {
    static let keyEnabled = "poof.airgap.enabled"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: keyEnabled) }
    }

    /// True if the host resolves to a private range (10.x, 172.16-31.x, 192.168.x)
    /// or ends in `.local` (mDNS). Also allows loopback and hostnames without dots.
    static func isLAN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasSuffix(".local") {
            return true
        }
        if !host.contains(".") {
            return true
        }

        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        if a == 10 {
            return true
        }
        if a == 192, b == 168 {
            return true
        }
        if a == 172, (16 ... 31).contains(b) {
            return true
        }
        return false
    }
}
