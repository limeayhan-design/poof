import SwiftUI
import QuickLook

// Received files + universal clipboard toggle + clipboard history.

struct HistorySheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        universalClipboardSection
                        Divider().background(PoofTheme.glassStroke)
                        receivedFilesSection
                        Divider().background(PoofTheme.glassStroke)
                        clipboardSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(PoofTheme.accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !session.receivedFiles.isEmpty {
                        Button {
                            session.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(PoofTheme.danger)
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { previewURL.map(IdentifiableURL.init) },
                set: { previewURL = $0?.url }
            )) { wrapped in
                ReceivedFileSheet(url: wrapped.url).environmentObject(session)
            }
        }
    }

    // MARK: - Universal Clipboard toggle

    private var universalClipboardSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 16))
                .foregroundColor(PoofTheme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Universal Clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                Text("Auto-sync your clipboard with the connected device.")
                    .font(.system(size: 12))
                    .foregroundColor(PoofTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $session.universalClipboardEnabled)
                .labelsHidden()
                .tint(PoofTheme.accent)
        }
        .padding(12)
        .glassCard()
    }

    // MARK: - Received files

    private var receivedFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Received files")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                if !session.receivedFiles.isEmpty {
                    Text("\(session.receivedFiles.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            if session.receivedFiles.isEmpty {
                Text("No files received yet.")
                    .font(.system(size: 13))
                    .foregroundColor(PoofTheme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                ForEach(session.receivedFiles) { file in
                    Button {
                        previewURL = file.url
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconFor(name: file.name))
                                .font(.system(size: 16))
                                .foregroundColor(PoofTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(PoofTheme.textPrimary)
                                    .lineLimit(1)
                                Text("\(formatBytes(file.size)) · \(relativeDate(file.date))")
                                    .font(.system(size: 11))
                                    .foregroundColor(PoofTheme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(PoofTheme.textTertiary)
                        }
                        .padding(12)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Clipboard history

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clipboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)

            if session.clipboard.history.isEmpty {
                Text("No clipboard activity yet.")
                    .font(.system(size: 13))
                    .foregroundColor(PoofTheme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                ForEach(Array(session.clipboard.history.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.origin == .local ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(item.origin == .local ? PoofTheme.accent2 : PoofTheme.accent)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                        Text(item.text)
                            .font(.system(size: 13))
                            .foregroundColor(PoofTheme.textPrimary)
                            .lineLimit(4)
                        Spacer()
                    }
                    .padding(12)
                    .glassCard()
                    .onTapGesture {
                        UIPasteboard.general.string = item.text
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func iconFor(name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv":            return "video.fill"
        case "mp3", "m4a", "wav", "aiff", "flac":          return "waveform"
        case "pdf":                                        return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz":              return "archivebox.fill"
        case "txt", "md":                                  return "doc.text.fill"
        case "key", "pages", "numbers":                    return "doc.fill"
        default:                                           return "doc.fill"
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
