import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Root view — 3-tab layout matching the Figma (Home / Send / Library) with a
// floating FAB circle to the right of the tab pill. Owns every global sheet and
// file picker so the child screens stay pure presentation.

nonisolated struct IdentifiableURL: Identifiable, Hashable {
    let url: URL
    var id: String {
        url.absoluteString
    }
}

struct PoofRootView: View {
    enum Tab: Hashable { case home, send, received }

    @EnvironmentObject var session: PoofSession
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue

    @State private var selectedTab: Tab = .home

    // Global sheets
    @State private var showSendOptions = false
    @State private var showPairing = false
    @State private var showPricing = false
    @State private var showHistory = false
    @State private var showSendText = false
    @State private var previewURL: URL?

    // File pickers
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    /// Transient toast (surfaced from session.toast)
    @State private var toastText: String?

    private var tier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PoofBackground()

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

            if let toast = toastText {
                toastPill(toast)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSendOptions) {
            PoofSendOptionsSheet(
                onPickPhotos: {
                    showSendOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPhotoPicker = true
                    }
                },
                onPickFiles: {
                    showSendOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showFilePicker = true
                    }
                },
                onPushClipboard: {
                    showSendOptions = false
                    handleClipboardSend()
                }
            )
            .poofSheet(detents: [.medium], tinted: true)
        }
        .sheet(isPresented: $showPairing) {
            PairingSheet()
                .environmentObject(session)
                .poofSheet()
        }
        .sheet(isPresented: $showPricing) {
            PricingSheet()
                .poofSheet()
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet()
                .environmentObject(session)
                .poofSheet()
        }
        .sheet(isPresented: $showSendText) {
            SendTextSheet()
                .environmentObject(session)
                .poofSheet(detents: [.medium, .large])
        }
        .sheet(item: Binding(
            get: { previewURL.map(IdentifiableURL.init) },
            set: { previewURL = $0?.url }
        )) { wrapped in
            PoofReceivedFileSheet(url: wrapped.url)
                .environmentObject(session)
                .poofSheet()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            haptic()
            handleFileSelection(urls)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePhotoSelection(items) }
        }
        .onChange(of: session.toast) { _, new in
            guard let new else { return }
            flash(new)
            session.toast = nil
        }
        .onChange(of: session.lastIncomingFile) { _, new in
            if let new {
                previewURL = new
            }
        }
        .alert(
            "Approve incoming file?",
            isPresented: Binding(
                get: { session.pendingKidReview != nil },
                set: {
                    if !$0 {
                        session.blockKidFile()
                    }
                }
            ),
            presenting: session.pendingKidReview
        ) { _ in
            Button("Approve") { session.approveKidFile() }
            Button("Block", role: .destructive) { session.blockKidFile() }
        } message: { pending in
            Text(verbatim: pending.peerName + " wants to send \"" + pending.name + "\"")
        }
        .onAppear { session.start() }
        // Extraction en modifier — sans ça le body chaîne 4 sheets + alert +
        // 3 onChange + 4 onReceive → type-check explose (« unable to type-check
        // in reasonable time »). Le modifier isole les 4 onReceive App Intents.
        .modifier(AppIntentsWiring(
            onSendClipboard: { handleClipboardSend() },
            onOpenSend: {
                selectedTab = .send
                showSendOptions = true
            },
            onOpenPairing: { showPairing = true },
            onOpenPricing: { showPricing = true }
        ))
    }

    // MARK: - Toast

    /// Kind is inferred from the message text so callers stay unchanged.
    /// Each kind picks an SF Symbol + tint + notification haptic — the whole
    /// pill feels like a native iOS confirmation (Music "Added to Library",
    /// AirDrop "Sent").
    private enum ToastKind {
        case success, error, info, send, receive

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "xmark.circle.fill"
            case .info: "info.circle.fill"
            case .send: "paperplane.fill"
            case .receive: "tray.and.arrow.down.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: Color(red: 0.20, green: 0.78, blue: 0.35)
            case .error: Color(red: 1.0, green: 0.36, blue: 0.32)
            case .info: .white
            case .send: PoofTheme.blueStart
            case .receive: PoofTheme.blueStart
            }
        }
    }

    private func toastKind(from text: String) -> ToastKind {
        let l = text.lowercased()
        if l.contains("over") || l.contains("nothing") || l.contains("fail") {
            return .error
        }
        if l.contains("sent") || l.contains("added") {
            return .success
        }
        if l.contains("sending") {
            return .send
        }
        if l.contains("received") || l.contains("downloaded") {
            return .receive
        }
        return .info
    }

    private func toastPill(_ text: String) -> some View {
        let kind = toastKind(from: text)
        return HStack(spacing: 8) {
            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(kind.tint)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private func flash(_ text: String) {
        // Fire an haptic assorted to the message so success/failure lands
        // in the fingers even before the user reads the pill.
        switch toastKind(from: text) {
        case .success: PoofHaptics.success()
        case .error: PoofHaptics.error()
        case .send: PoofHaptics.sendStart()
        case .receive: PoofHaptics.receive()
        case .info: PoofHaptics.tap()
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toastText == text {
                withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        switch style {
        case .soft: PoofHaptics.soft()
        case .medium: PoofHaptics.impactMedium()
        case .heavy, .rigid: PoofHaptics.impactMedium()
        default: PoofHaptics.tap()
        }
    }

    // MARK: - Actions

    private func handleClipboardSend() {
        guard requireActiveSession() else { return }
        haptic()
        if let summary = session.pushClipboardRich() {
            flash(summary)
        } else {
            flash("Nothing on the clipboard")
        }
    }

    @discardableResult
    private func requireActiveSession() -> Bool {
        if session.isRTCConnected {
            return true
        }
        if session.peers.peers.isEmpty {
            flash("Pair a device first")
            selectedTab = .send
            return false
        }
        if session.activePeerId == nil, let first = session.peers.peers.first {
            session.openSession(with: first.id)
            flash("Connecting to \(first.name)…")
            return false
        }
        flash("Waiting for connection…")
        return false
    }

    private func handleFileSelection(_ urls: [URL]) {
        guard requireActiveSession() else { return }
        var sent = 0
        var oversize = 0
        var skippedFolders = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if tier.canDropFolders {
                    sent += sendFolderContents(from: url, oversize: &oversize)
                } else {
                    skippedFolders += 1
                }
                continue
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            if !tier.canSendFile(size: size) {
                oversize += 1
                continue
            }
            if sendSingleFile(from: url) {
                sent += 1
            }
        }
        if skippedFolders > 0 {
            flash("Folder drop is a Premium feature")
            showPricing = true
        } else if oversize > 0 {
            flash("Over \(tier.maxFileSizeLabel) — upgrade for unlimited size")
        } else if sent > 0 {
            flash(sent == 1 ? "Sending 1 file…" : "Sending \(sent) files…")
        }
    }

    /// Recursively enumerates a picked folder and sends every regular file inside.
    /// Returns the count of files actually queued for send.
    private func sendFolderContents(from folder: URL, oversize: inout Int) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let size = UInt64(values?.fileSize ?? 0)
            if !tier.canSendFile(size: size) {
                oversize += 1
                continue
            }
            if sendSingleFile(from: fileURL) {
                count += 1
            }
        }
        return count
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) async {
        guard requireActiveSession() else {
            await MainActor.run { selectedPhotos = [] }
            return
        }
        var sent = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
            let name = "photo-\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PoofOutgoing", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(name)
            do {
                try data.write(to: dest)
                await MainActor.run { session.sendFile(at: dest, mime: mime) }
                sent += 1
            } catch { continue }
        }
        await MainActor.run {
            selectedPhotos = []
            if sent > 0 {
                flash(sent == 1 ? "Sending 1 photo…" : "Sending \(sent) items…")
            }
        }
    }

    private func sendSingleFile(from url: URL) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofOutgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let mime = UTType(filenameExtension: dest.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            session.sendFile(at: dest, mime: mime)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Sheet presentation signature

// One modifier so every sheet inherits the same corner radius, drag indicator,
// and (optionally) the blue tint that echoes the hero card the user just tapped.

extension View {
    /// Apply the Poof sheet look. `tinted` = true adds the blue wash used by the
    /// SendOptions sheet, which prolongs the hero card visually.
    func poofSheet(
        detents: Set<PresentationDetent> = [.large],
        tinted: Bool = false
    ) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(PoofTokens.radiusCard)
            .presentationBackground {
                if tinted {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        LinearGradient(
                            colors: [
                                PoofTheme.blueStart.opacity(0.55),
                                PoofTheme.blueEnd.opacity(0.45)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()
                } else {
                    Rectangle()
                        .fill(PoofTokens.canvas)
                        .ignoresSafeArea()
                }
            }
    }
}

// MARK: - App Intents wiring modifier

/// Bundle des 4 `.onReceive(...)` App Intents en un seul modifier — sortis
/// du body principal pour éviter le type-check timeout SwiftUI ("unable to
/// type-check in reasonable time") quand la chaîne des modifiers dépasse
/// une dizaine d'appels enchaînés.
private struct AppIntentsWiring: ViewModifier {
    let onSendClipboard: () -> Void
    let onOpenSend: () -> Void
    let onOpenPairing: () -> Void
    let onOpenPricing: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .poofSendClipboard)) { _ in
                onSendClipboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .poofOpenSend)) { _ in
                onOpenSend()
            }
            .onReceive(NotificationCenter.default.publisher(for: .poofOpenPairing)) { _ in
                onOpenPairing()
            }
            .onReceive(NotificationCenter.default.publisher(for: .poofOpenPricing)) { _ in
                onOpenPricing()
            }
    }
}
