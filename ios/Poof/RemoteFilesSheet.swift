import SwiftUI

// Browses the paired peer's Documents/ folder. Tap a file to pull it — arrives
// through the standard file-transfer flow (progress + History).

struct RemoteFilesSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var path: String = ""
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var lastRequestId: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                content
            }
            .navigationTitle("Remote Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !path.isEmpty {
                        Button {
                            navigateUp()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(PoofTheme.accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(PoofTheme.accent)
                }
            }
            .onAppear {
                session.remote.onListReceived = { requestId, receivedPath, list in
                    Task { @MainActor in
                        guard requestId == self.lastRequestId else { return }
                        self.path = receivedPath
                        self.entries = list
                        self.loading = false
                    }
                }
                refresh()
            }
            .onDisappear {
                session.remote.onListReceived = nil
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !session.isRTCConnected {
            offlineState
        } else if loading && entries.isEmpty {
            loadingState
        } else if entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var offlineState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(PoofTheme.textTertiary)
            Text("No peer connected")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            Text("Pair a device and open a session to browse its files.")
                .font(.system(size: 12))
                .foregroundColor(PoofTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(PoofTheme.accent)
            Text("Loading \(displayPath)…")
                .font(.system(size: 12))
                .foregroundColor(PoofTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(PoofTheme.textTertiary)
            Text("Empty folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(PoofTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pathBreadcrumb
                ForEach(entries) { entry in
                    row(for: entry)
                }
            }
            .padding(16)
        }
    }

    private var pathBreadcrumb: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(PoofTheme.accent)
            Text(displayPath)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var displayPath: String {
        path.isEmpty ? "Documents" : "Documents/\(path)"
    }

    private func row(for entry: RemoteEntry) -> some View {
        Button {
            if entry.isDir { navigate(into: entry.name) }
            else { pull(entry) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDir ? "folder.fill" : "doc.fill")
                    .font(.system(size: 16))
                    .foregroundColor(entry.isDir ? PoofTheme.accent : PoofTheme.accent2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .lineLimit(1)
                    Text(entry.isDir ? "Folder" : formatBytes(entry.size))
                        .font(.system(size: 11))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                Spacer()
                Image(systemName: entry.isDir ? "chevron.right" : "arrow.down.circle.fill")
                    .font(.system(size: entry.isDir ? 11 : 15, weight: entry.isDir ? .bold : .semibold))
                    .foregroundColor(entry.isDir ? PoofTheme.textTertiary : PoofTheme.accent)
            }
            .padding(12)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private func navigate(into name: String) {
        let newPath = path.isEmpty ? name : "\(path)/\(name)"
        path = newPath
        refresh()
    }

    private func navigateUp() {
        var comps = path.split(separator: "/")
        if !comps.isEmpty { comps.removeLast() }
        path = comps.joined(separator: "/")
        refresh()
    }

    private func refresh() {
        guard session.isRTCConnected else { return }
        loading = true
        errorText = nil
        lastRequestId = session.remote.requestList(path: path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if loading {
                loading = false
                errorText = "No response from peer"
            }
        }
    }

    private func pull(_ entry: RemoteEntry) {
        let target = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
        session.remote.requestGet(path: target)
        session.toast = "Pulling \(entry.name)…"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
