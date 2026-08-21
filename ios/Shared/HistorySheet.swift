import QuickLook
import SwiftUI

/// Wrapper Identifiable local — évite la dépendance sur `IdentifiableURL`
/// défini dans le target iOS `PoofRootView.swift`. HistorySheet vit dans
/// `Shared/` pour être compilée sur iOS + macOS.
private struct HistoryURLBox: Identifiable, Hashable {
    let url: URL
    var id: String {
        url.absoluteString
    }
}

// History plein écran — même DNA visuelle que Send/Received (gradient bleu
// Poof, panneau glass, décor cloud). Segmented picker Received / Sent /
// Clipboard, contenu qui bascule sans dérouter l'utilisateur.

struct HistorySheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue
    @State private var previewURL: URL?
    @State private var selectedTab: HistoryTab = .received

    enum HistoryTab: String, CaseIterable, Identifiable {
        case received, sent, clipboard
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .received: "Received"
            case .sent: "Sent"
            case .clipboard: "Clipboard"
            }
        }

        var icon: String {
            switch self {
            case .received: "tray.and.arrow.down.fill"
            case .sent: "paperplane.fill"
            case .clipboard: "doc.on.clipboard.fill"
            }
        }
    }

    private var tier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    /// Applies the Free-tier 24h purge to any [ReceivedFile]-like list.
    /// Premium returns the list intact.
    private func withinRetention<T>(_ items: [T], date: (T) -> Date) -> [T] {
        guard let hours = tier.maxHistoryAgeHours else { return items }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return items.filter { date($0) >= cutoff }
    }

    private var visibleReceivedFiles: [PoofSession.ReceivedFile] {
        withinRetention(session.receivedFiles, date: \.date)
            .sorted { $0.date > $1.date }
    }

    private var visibleSentFiles: [PoofSentFile] {
        withinRetention(session.sentFiles, date: \.date)
            .sorted { $0.date > $1.date }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            panel
                .frame(width: 370, height: 480)
                .offset(y: -20)

            Image("HeroPhoto")
                .resizable()
                .scaledToFit()
                .frame(width: 600)
                .opacity(0.75)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 40)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 24) // room pour la drag indicator de la sheet
        }
        .sheet(item: Binding(
            get: { previewURL.map(HistoryURLBox.init) },
            set: { previewURL = $0?.url }
        )) { wrapped in
            PoofReceivedFileSheet(url: wrapped.url).environmentObject(session)
        }
    }

    // MARK: - Top bar (Poof title + close)

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                PoofHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Panel glass + contenu

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            segmentedPicker
            currentContent
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(HistoryTab.allCases) { tab in
                segmentedButton(tab)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
    }

    private func segmentedButton(_ tab: HistoryTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            PoofHaptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isActive ? .black : .white)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(isActive ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contenu par tab

    @ViewBuilder
    private var currentContent: some View {
        switch selectedTab {
        case .received: receivedContent
        case .sent: sentContent
        case .clipboard: clipboardContent
        }
    }

    // MARK: Received

    @ViewBuilder
    private var receivedContent: some View {
        let files = visibleReceivedFiles
        if files.isEmpty {
            emptyState(icon: "tray.and.arrow.down", title: "No files received yet")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(files) { file in
                        HistoryFileTile(file: file) { previewURL = file.url }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: Sent

    @ViewBuilder
    private var sentContent: some View {
        let files = visibleSentFiles
        if files.isEmpty {
            emptyState(icon: "paperplane", title: "No files sent yet")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(files) { file in
                        sentRow(file)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func sentRow(_ file: PoofSentFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(name: file.name))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("to \(file.peerName) · \(formatBytes(file.size)) · \(relativeDate(file.date))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
            if let count = openCount(for: file.id), count > 0 {
                trackViewBadge(count)
            }
            if tier.canUseReadReceipts {
                receiptBadge(file.receipt)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    /// Compteur d'ouvertures pour un fichier envoyé — lit `trackEvents`
    /// et filtre les events de kind `.opened`. Nil = jamais ouvert.
    private func openCount(for id: UUID) -> Int? {
        session.trackEvents[id]?.filter { $0.kind == .opened }.count
    }

    /// Badge compteur de vues façon iMessage. Cliquable → toast affichant
    /// le dernier device qui a ouvert.
    private func trackViewBadge(_ count: Int) -> some View {
        Button {
            PoofHaptics.tap()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func receiptBadge(_ state: PoofReceiptState) -> some View {
        let tint: Color = state == .seen
            ? Color(red: 0.35, green: 0.85, blue: 0.55)
            : state == .delivered
            ? .white
            : .white.opacity(0.5)
        return HStack(spacing: 4) {
            Image(systemName: state.icon)
                .font(.system(size: 10, weight: .bold))
            Text(state.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.18)))
    }

    // MARK: Clipboard

    @ViewBuilder
    private var clipboardContent: some View {
        let items = session.clipboard.history
        if items.isEmpty {
            emptyState(icon: "doc.on.clipboard", title: "No clipboard activity yet")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        clipboardRow(item)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func clipboardRow(_ item: PoofClipboardSync.Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.origin == .local ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.14)))
            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .onTapGesture {
            PoofPlatform.setClipboardString(item.text)
            PoofHaptics.success()
        }
    }

    // MARK: Empty state

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(20)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            if !tier.isPremium {
                Text("Free plan keeps 24h. Premium unlocks full history.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func iconFor(name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv": return "video.fill"
        case "mp3", "m4a", "wav", "aiff", "flac": return "waveform"
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tile fichier reçu (dupliquée du received tab pour scope isolé)

private struct HistoryFileTile: View {
    let file: PoofSession.ReceivedFile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.85))

                if isSecureLocked {
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                } else if isImage {
                    AsyncImage(url: file.url) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(Color(white: 0.45))
                        }
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color(white: 0.45))
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(shortTime)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                        badgesRow
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(HistoryTileBounce())
    }

    private var isImage: Bool {
        let ext = file.url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp"].contains(ext)
    }

    /// Vrai si le fichier a un passcode OU biometrics Secure — preview cachée
    /// (cadenas + fond gris) tant que le user n'a pas passé le gate.
    private var isSecureLocked: Bool {
        guard let cfg = file.secureConfig else { return false }
        return cfg.passcode.isEnabled || cfg.biometrics
    }

    private var badgesRow: some View {
        HStack(spacing: 3) {
            if file.secureConfig != nil {
                badge("lock.shield.fill")
            }
            if file.trackConfig != nil {
                badge("eye.fill")
            }
        }
    }

    private func badge(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
    }

    private var icon: String {
        let ext = file.url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) {
            return "photo.fill"
        }
        if ["mp4", "mov", "m4v"].contains(ext) {
            return "film.fill"
        }
        if ["pdf"].contains(ext) {
            return "doc.richtext.fill"
        }
        return "doc.fill"
    }

    private var shortTime: String {
        let calendar = Calendar.current
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "HH:mm"
        if calendar.isDateInToday(file.date) {
            return df.string(from: file.date)
        }
        if calendar.isDateInYesterday(file.date) {
            return "hier " + df.string(from: file.date)
        }
        df.dateFormat = "dd/MM"
        return df.string(from: file.date)
    }
}

private struct HistoryTileBounce: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
