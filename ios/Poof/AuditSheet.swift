import SwiftUI
import UIKit

// Business tier: consolidated log of every transfer this device has seen,
// filterable, exportable as CSV via the iOS share sheet.

struct AuditSheet: View {
    @EnvironmentObject private var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BusinessWorkspace.keyColor) private var color: String = BusinessWorkspace.defaultColor

    enum Filter: String, CaseIterable, Identifiable {
        case all, sent, received
        var id: String {
            rawValue
        }

        var label: String {
            rawValue.capitalized
        }
    }

    @State private var filter: Filter = .all
    @State private var exportURL: URL?
    @State private var showShare = false

    private var accent: Color {
        Color(hex: color) ?? PoofTier.business.accent
    }

    struct Entry: Identifiable {
        let id: String
        let direction: String // "sent" or "received"
        let name: String
        let size: UInt64
        let peer: String
        let date: Date
        let receipt: String?
    }

    private var entries: [Entry] {
        var out: [Entry] = []
        if filter != .received {
            for f in session.sentFiles {
                out.append(Entry(
                    id: "s-\(f.id)",
                    direction: "sent",
                    name: f.name,
                    size: f.size,
                    peer: f.peerName,
                    date: f.date,
                    receipt: f.receipt.label.lowercased()
                ))
            }
        }
        if filter != .sent {
            for f in session.receivedFiles {
                out.append(Entry(
                    id: "r-\(f.id)",
                    direction: "received",
                    name: f.name,
                    size: f.size,
                    peer: "—",
                    date: f.date,
                    receipt: nil
                ))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                VStack(spacing: 12) {
                    filterBar
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(entries) { e in row(e) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Live audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(accent)
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(filter == f ? .white : PoofTheme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(filter == f ? accent : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(entries.count) event\(entries.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(PoofTheme.textTertiary)
            Text("No activity yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PoofTheme.textSecondary)
            Text("Your transfers will land here in real time.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PoofTheme.textTertiary)
            Spacer()
        }
    }

    private func row(_ e: Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: e.direction == "sent" ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(e.direction == "sent" ? accent : PoofTheme.green)
                .frame(width: 22, height: 22)
                .background(Circle().fill((e.direction == "sent" ? accent : PoofTheme.green).opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(e.direction == "sent" ? "to \(e.peer)" : "received")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                    if let r = e.receipt {
                        Text("· \(r)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PoofTheme.textTertiary)
                    }
                    Text("· \(formatBytes(e.size))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Text(relative(e.date))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusSm)
    }

    private func relative(_ d: Date) -> String {
        let s = -Int(d.timeIntervalSinceNow)
        if s < 60 {
            return "just now"
        }
        if s < 3600 {
            return "\(s / 60)m"
        }
        if s < 86400 {
            return "\(s / 3600)h"
        }
        return "\(s / 86400)d"
    }

    private func formatBytes(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }

    private func exportCSV() {
        let iso = ISO8601DateFormatter()
        var csv = "timestamp,direction,name,size_bytes,peer,receipt\n"
        for e in entries {
            let peer = e.peer.replacingOccurrences(of: "\"", with: "\"\"")
            let name = e.name.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(iso.string(from: e.date)),\(e.direction),\"\(name)\",\(e.size),\"\(peer)\",\(e.receipt ?? "")\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poof-audit-\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.data(using: .utf8)?.write(to: url)
        exportURL = url
        showShare = true
    }
}
