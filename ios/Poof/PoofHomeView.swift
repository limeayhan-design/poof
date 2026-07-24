import SwiftUI
import UniformTypeIdentifiers

nonisolated struct IdentifiableURL: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

// Main screen — mirrors pc/index.html:
//   Header (title + status + settings) → workspace tabs → transfer pill →
//   drop zone → paired devices → clipboard card → 3 bottom action tiles.

struct PoofHomeView: View {
    @EnvironmentObject var session: PoofSession
    @State private var workspace: Workspace = .standard
    @State private var showSettings = false
    @State private var showSendText = false
    @State private var showHistory = false
    @State private var showFilePicker = false
    @State private var toastText: String?
    @State private var previewURL: URL?

    enum Workspace: String { case standard, premium, devium }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func flash(_ text: String) {
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if toastText == text { toastText = nil }
        }
    }

    var body: some View {
        ZStack {
            PoofBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    workspaceTabs
                    if let t = session.incomingTransfer { transferPill(t) }
                    dropZone
                    devicesSection
                    clipboardCard
                    bottomActions
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }

            if let toast = toastText {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettings) {
            PairingSheet().environmentObject(session)
        }
        .sheet(isPresented: $showSendText) {
            SendTextSheet().environmentObject(session)
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet().environmentObject(session)
        }
        .sheet(item: Binding(
            get: { previewURL.map(IdentifiableURL.init) },
            set: { previewURL = $0?.url }
        )) { wrapped in
            ReceivedFileSheet(url: wrapped.url).environmentObject(session)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            haptic()
            handleFileSelection(urls)
        }
        .onChange(of: session.toast) { _, new in
            guard let new else { return }
            flash(new)
            session.toast = nil
        }
        .onChange(of: session.lastIncomingFile) { _, new in
            if let new { previewURL = new }
        }
        .onAppear { session.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Poof")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(PoofTheme.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                statusBadge
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(alignment: .topTrailing) {
                            if !session.receivedFiles.isEmpty || session.lastIncomingText != nil {
                                Circle().fill(PoofTheme.accent)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(PoofTheme.bgBase, lineWidth: 2))
                                    .offset(x: -4, y: 4)
                            }
                        }
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.95)))
                }
            }
        }
    }

    private var statusBadge: some View {
        let (text, dotColor) = statusDescriptor()
        return HStack(spacing: 6) {
            Circle().fill(dotColor)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCard(radius: 20)
    }

    private func statusDescriptor() -> (String, Color) {
        if !session.isSignalingConnected { return ("Offline", PoofTheme.textTertiary) }
        if session.isRTCConnected        { return ("Online",  PoofTheme.green) }
        if session.activePeerId != nil   { return ("Connecting…", PoofTheme.accent2) }
        return ("Ready", PoofTheme.accent)
    }

    // MARK: - Workspace tabs

    private var workspaceTabs: some View {
        HStack(spacing: 8) {
            wsTab(.standard, dot: PoofTheme.green, locked: false)
            wsTab(.premium, dot: PoofTheme.accent2, locked: true)
            wsTab(.devium, dot: PoofTheme.accent, locked: true)
        }
    }

    private func wsTab(_ ws: Workspace, dot: Color, locked: Bool) -> some View {
        let active = workspace == ws
        return Button {
            if locked {
                toastText = ws == .premium
                    ? "Premium — coming soon. Get notified on poof.app"
                    : "Devium — for developers. Launching after Premium."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { toastText = nil }
            } else {
                workspace = ws
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(ws.rawValue.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(active ? PoofTheme.textPrimary : PoofTheme.textSecondary)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PoofTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(active ? PoofTheme.accent.opacity(0.7) : .clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transfer pill

    private func transferPill(_ t: PoofSession.TransferProgress) -> some View {
        let ratio = t.total > 0 ? Double(t.received) / Double(t.total) : 0
        return HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 16))
                .foregroundColor(PoofTheme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(ratio * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(PoofTheme.accent)
                            .frame(width: geo.size.width * CGFloat(ratio))
                    }
                }.frame(height: 5)
            }
            Button {
                haptic(.medium)
                session.files.cancel(t.id, reason: "user")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(PoofTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassCard()
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        Button {
            haptic()
            showFilePicker = true
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(PoofTheme.dropStroke, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                        .frame(width: 42, height: 58)
                    VStack(spacing: 6) {
                        Capsule().fill(PoofTheme.dropStroke).frame(width: 24, height: 2)
                        Capsule().fill(PoofTheme.dropStroke).frame(width: 24, height: 2)
                        Capsule().fill(PoofTheme.dropStroke).frame(width: 16, height: 2)
                    }
                }
                Text("Tap to send a file")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PoofTheme.textSecondary)
                Text("Photos, videos, PDFs, anything")
                    .font(.system(size: 11))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .glassCard(radius: PoofTheme.radiusLg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Devices

    private var devicesSection: some View {
        VStack(spacing: 8) {
            if session.peers.peers.isEmpty {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(PoofTheme.accent)
                    Text("Add a device")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                    Spacer()
                }
                .padding(14)
                .glassCard()
                .onTapGesture { showSettings = true }
            } else {
                ForEach(session.peers.peers) { peer in
                    deviceRow(peer)
                }
            }
        }
    }

    private func deviceRow(_ peer: PairedPeer) -> some View {
        let online = session.isPeerOnline(peer.id)
        let active = session.activePeerId == peer.id
        let rtc = active && session.isRTCConnected
        return Button {
            haptic()
            if active {
                if rtc { flash("Already connected to \(peer.name)") }
            } else {
                session.openSession(with: peer.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: platformIcon(peer.platform))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Text(rowStatus(active: active, rtc: rtc, online: online))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(rowStatusColor(active: active, rtc: rtc, online: online))
                }
                Spacer()
                if rtc {
                    Text("Connected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.green)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(PoofTheme.green.opacity(0.18)))
                } else if active {
                    Text("Opening…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.accent2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(PoofTheme.accent2.opacity(0.18)))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PoofTheme.textTertiary)
                }
            }
            .padding(12)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: PoofTheme.radiusMd)
                    .strokeBorder(active ? PoofTheme.accent : .clear, lineWidth: active ? 1.6 : 0)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                haptic(.medium)
                session.unpair(peer.id)
                flash("Unpaired \(peer.name)")
            } label: {
                Label("Unpair", systemImage: "trash")
            }
        }
    }

    private func rowStatus(active: Bool, rtc: Bool, online: Bool) -> String {
        if rtc { return "Ready to send" }
        if active { return "Connecting…" }
        if online { return "Online · Tap to connect" }
        return "Tap to connect"
    }

    private func rowStatusColor(active: Bool, rtc: Bool, online: Bool) -> Color {
        if rtc { return PoofTheme.green }
        if active { return PoofTheme.accent2 }
        if online { return PoofTheme.textSecondary }
        return PoofTheme.textTertiary
    }

    private func platformIcon(_ platform: String) -> String {
        switch platform {
        case "mac", "macos":   return "desktopcomputer"
        case "ios-pad":        return "ipad"
        case "ios":            return "iphone"
        case "windows", "win": return "pc"
        case "linux":          return "terminal"
        case "android":        return "candybarphone"
        default:               return "questionmark.circle"
        }
    }

    // MARK: - Clipboard card

    @ViewBuilder
    private var clipboardCard: some View {
        if let text = session.lastIncomingText, !text.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(PoofTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundColor(PoofTheme.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .glassCard()
            .onTapGesture {
                UIPasteboard.general.string = text
                toastText = "Copied"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { toastText = nil }
            }
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: 8) {
            if let name = activeTargetName {
                HStack(spacing: 6) {
                    Circle().fill(PoofTheme.green).frame(width: 6, height: 6)
                    Text("Sending to \(name)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if !session.peers.peers.isEmpty {
                Text("Tap a device above to select a target")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PoofTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 12) {
                actionTile(icon: "text.alignleft", label: "Send Text") {
                    guard requireActiveSession() else { return }
                    haptic()
                    showSendText = true
                }
                actionTile(icon: "doc.badge.plus", label: "Send File") {
                    guard requireActiveSession() else { return }
                    haptic()
                    showFilePicker = true
                }
                actionTile(icon: "doc.on.clipboard", label: "Push Clipboard") {
                    guard requireActiveSession() else { return }
                    haptic()
                    session.pushClipboard()
                    flash("Clipboard sent")
                }
            }
        }
    }

    private var activeTargetName: String? {
        guard session.isRTCConnected, let id = session.activePeerId else { return nil }
        return session.peers.peers.first(where: { $0.id == id })?.name
    }

    @discardableResult
    private func requireActiveSession() -> Bool {
        if session.isRTCConnected { return true }
        if session.peers.peers.isEmpty {
            flash("Pair a device first")
            return false
        }
        // Auto-open with the first paired device
        if session.activePeerId == nil, let first = session.peers.peers.first {
            session.openSession(with: first.id)
            flash("Connecting to \(first.name)…")
            return false
        }
        flash("Waiting for connection…")
        return false
    }

    private func actionTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(PoofTheme.textSecondary)
                    .frame(height: 28)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PoofTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .contentShape(Rectangle())
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - File picker

    private func handleFileSelection(_ urls: [URL]) {
        var sent = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

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
                sent += 1
            } catch {
                continue
            }
        }
        if sent > 0 { flash(sent == 1 ? "Sending 1 file…" : "Sending \(sent) files…") }
    }
}
