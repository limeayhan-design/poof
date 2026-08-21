import SwiftUI

@main
struct PoofApp: App {
    // AppDelegate adapter — permet à SwiftUI de recevoir le callback APNS
    // `didRegisterForRemoteNotificationsWithDeviceToken`. Sans adapter, aucun
    // moyen d'attraper le device token via .task ou .onAppear.
    @UIApplicationDelegateAdaptor(PoofAppDelegate.self) private var appDelegate
    @StateObject private var session = PoofSession()
    // Nouveau flag séparé de l'ancien "poof.hasOnboarded" — le vieux onboarding
    // (relay URL LAN) est obsolète depuis qu'on force Render. On veut que
    // même les users qui avaient marqué `hasOnboarded=true` voient la
    // nouvelle version welcome multi-slides.
    @AppStorage("poof.hasOnboarded.v2") private var hasOnboardedV2: Bool = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PoofRootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    PoofTrackNotifier.requestAuthIfNeeded()
                    // Wire le token APNS → serveur signaling pour push relay.
                    PoofPushManager.shared.onTokenReceived = { token in
                        session.registerPushToken(token)
                    }
                    PoofPushManager.shared.register()
                    await session.drainSharedInbox()
                    // Trigger onboarding V2 la 1re fois — le flag est setter
                    // par le sheet à la fin via session.completeOnboarding().
                    if !hasOnboardedV2 {
                        showOnboarding = true
                    }
                }
                .sheet(isPresented: $showOnboarding, onDismiss: {
                    // Le sheet est setDismissible only via completeOnboarding
                    // (interactiveDismissDisabled), donc si on arrive ici =
                    // l'user a bien fini. On persiste le flag pour ne plus
                    // le réafficher.
                    hasOnboardedV2 = true
                }) {
                    PoofOnboardingSheet().environmentObject(session)
                }
                .premiumPaywallSheet()
                .nearbyInvitationSheet()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: session.enterBackground()
                    case .active: session.returnToForeground()
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
