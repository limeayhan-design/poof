import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Wrapper Identifiable pour utiliser `.sheet(item:)` avec un URL — évite
/// de dupliquer la logique iOS `IdentifiableURL`.
private struct MacURLBox: Identifiable {
    let url: URL
    var id: String {
        url.absoluteString
    }
}

@main
struct PoofMacApp: App {
    // AppDelegate adapter pour recevoir le device token APNS via
    // `didRegisterForRemoteNotificationsWithDeviceToken` sur macOS.
    @NSApplicationDelegateAdaptor(PoofAppDelegate.self) private var appDelegate
    @StateObject private var session = PoofSession()

    var body: some Scene {
        WindowGroup("Poof") {
            PoofMacWindow()
                .environmentObject(session)
                .frame(width: 400, height: 860)
                .task {
                    session.start()
                    PoofTrackNotifier.requestAuthIfNeeded()
                    PoofPushManager.shared.onTokenReceived = { token in
                        session.registerPushToken(token)
                    }
                    PoofPushManager.shared.register()
                    // Menu bar item — bouton « 📋 Coller dernier clipboard »
                    // persistant en haut de l'écran, colle sans ouvrir l'app.
                    PoofMenuBarController.shared.install()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 860)
    }
}

/// Fenêtre Mac locked à 400×860 : miroir 1:1 du design iPhone avec la même
/// tab bar Home / Send / Received. Réutilise les 3 views Shared/.
private struct PoofMacWindow: View {
    enum Tab: Hashable { case home, send, received }

    @EnvironmentObject var session: PoofSession
    @State private var selectedTab: Tab = .send
    @State private var showPairing = false
    @State private var showSendOptions = false
    @State private var showPricing = false
    @State private var showHistory = false
    @State private var toastText: String?
    @State private var previewURL: URL?
    @State private var showFilePicker: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            PoofHomeView(
                onGoToSend: { selectedTab = .send },
                onOpenPricing: { showPricing = true }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            PoofSendView(
                onOpenSendSheet: { showSendOptions = true },
                onOpenPairing: { showPairing = true }
            )
            .tabItem { Label("Send", systemImage: "paperplane.fill") }
            .tag(Tab.send)

            PoofReceivedView(
                onOpenHistory: { showHistory = true },
                onPreviewFile: { url in previewURL = url }
            )
            .tabItem { Label("Received", systemImage: "tray.and.arrow.down.fill") }
            .tag(Tab.received)
        }
        .frame(width: 400, height: 860)
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $showPairing) {
            PoofAddDeviceSheet(onPair: { _ in showPairing = false })
                .environmentObject(session)
                .frame(width: 400, height: 700)
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet()
                .environmentObject(session)
                .frame(width: 480, height: 720)
        }
        .sheet(isPresented: $showPricing) {
            // Pré-launch : on affiche l'écran « Coming soon » + reward beta
            // au lieu du paywall payant (voir project_poof_premium_paused).
            PremiumComingSoonView()
                .frame(width: 480, height: 780)
        }
        .confirmationDialog(
            "Send",
            isPresented: $showSendOptions,
            titleVisibility: .visible
        ) {
            Button("Choose Files…") { pickFilesFromPanel() }
            Button("Send Clipboard") { sendClipboard() }
            Button("Cancel", role: .cancel) {}
        }
        // Preview cross-platform — même UI qu'iOS avec toutes les gates
        // Secure, watermark, message Track, save/share.
        .sheet(item: Binding(
            get: { previewURL.map(MacURLBox.init) },
            set: { previewURL = $0?.url }
        )) { wrapped in
            PoofReceivedFileSheet(url: wrapped.url)
                .environmentObject(session)
                .frame(width: 480, height: 720)
        }
        // File picker cross-platform natif — remplace le NSOpenPanel qui
        // ne s'affiche pas fiablement depuis un `confirmationDialog` Mac
        // (conflit de modals). SwiftUI gère la présentation proprement.
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                session.sendFile(at: url)
            }
        }
        .onChange(of: session.toast) { _, new in
            guard let new else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                toastText = new
            }
            session.toast = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if toastText == new {
                    withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
                }
            }
        }
        .onChange(of: session.lastIncomingFile) { _, new in
            guard let url = new, url != previewURL else { return }
            previewURL = url
        }
        .premiumPaywallSheet()
        .nearbyInvitationSheet()
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let text = toastText {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Ouvre le fileImporter SwiftUI après avoir laissé le confirmationDialog
    /// se fermer proprement — les 2 modals macOS ne peuvent pas cohabiter.
    private func pickFilesFromPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showFilePicker = true
        }
    }

    private func sendClipboard() {
        if let text = PoofPlatform.clipboardString, !text.isEmpty {
            session.sendText(text)
            session.toast = "Clipboard sent"
        } else {
            session.toast = "Nothing on the clipboard"
        }
    }
}
