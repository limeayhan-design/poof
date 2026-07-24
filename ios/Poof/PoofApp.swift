import SwiftUI

@main
struct PoofApp: App {
    @StateObject private var session = PoofSession()
    @State private var showOnboarding = !PoofSession.hasOnboarded
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PoofHomeView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task { await session.drainSharedInbox() }
                .sheet(isPresented: $showOnboarding) {
                    PoofOnboardingSheet().environmentObject(session)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: session.enterBackground()
                    case .active:     session.returnToForeground()
                    default: break
                    }
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Share Extension handoff: poof://share?drain=1
        if url.host == "share" {
            Task { await session.drainSharedInbox() }
            return
        }
        // Support both custom scheme poof://pair=CODE and web URL with #pair=CODE
        let raw = url.absoluteString
        let code = PairingSheet.extractPairCode(from: raw)
        guard !code.isEmpty, code.count <= 10 else { return }
        session.joinWithCode(code)
    }
}
