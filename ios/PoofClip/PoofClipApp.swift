import SwiftUI

// App Clip entry point. Zero heavy dependencies — no WebRTC, no signaling.
// The Clip is a landing page invoked from a QR code (poof.link/clip?peer=…).
// It reads the invocation URL, shows a hero with the sender's name, and hands
// off to the full Poof app (poof:// deep link) or prompts install via SKOverlay
// on the parent App Store card.

@main
struct PoofClipApp: App {
    @State private var pairCode: String? = nil
    @State private var peerName: String = "someone nearby"

    var body: some Scene {
        WindowGroup {
            PoofClipRootView(pairCode: pairCode, peerName: peerName)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    parse(url)
                }
                .onOpenURL { url in parse(url) }
        }
    }

    private func parse(_ url: URL) {
        // Accept both universal-link style (https://poof.link/clip?peer=abc&code=XYZ)
        // and custom-scheme fallback (poof://clip?peer=abc&code=XYZ).
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value {
            pairCode = code
        }
        if let peer = items.first(where: { $0.name == "peer" })?.value, !peer.isEmpty {
            peerName = peer
        }
    }
}
