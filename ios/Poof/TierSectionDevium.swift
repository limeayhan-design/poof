import SwiftUI
import UIKit

// Devium home section — "Dev cockpit".
// Shown above the drop zone when tier == .devium.
// Real data: session.peers.peers as Multi-Drop targets, real device name in CLI.

struct TierSectionDevium: View {
    @EnvironmentObject private var session: PoofSession
    @State private var airGapped = false
    @State private var previewFeature: FeaturePreview?

    private var cliCommand: String {
        if let peer = session.peers.peers.first {
            let slug = peer.name.lowercased().replacingOccurrences(of: " ", with: "-")
            return "poof send report.zip \(slug)"
        }
        return "poof send report.zip <peer>"
    }

    var body: some View {
        let accent = PoofTier.devium.accent
        let peers = session.peers.peers

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent)
                Text("Dev cockpit")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                Text("Devium")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
            }

            multiDropCard(peers: peers, accent: accent)

            cliCard(accent: accent)

            apiKeyCard(accent: accent)

            airGapCard(accent: accent)
        }
        .sheet(item: $previewFeature) { FeaturePreviewSheet(preview: $0) }
    }

    private func multiDropCard(peers: [PairedPeer], accent: Color) -> some View {
        Button {
            previewFeature = FeaturePreview(
                icon: "square.grid.2x2.fill",
                title: "Multi-Drop",
                tagline: "Broadcast a file to N devices at once",
                status: peers.isEmpty ? .available : .preview,
                description: peers.isEmpty
                    ? "Pair a few devices from the gear menu, then send one file to all of them in a single tap. WebRTC peer-to-peer, no cloud relay."
                    : "You have \(peers.count) paired device\(peers.count == 1 ? "" : "s") ready. Multi-Drop broadcasts your next transfer to all of them in parallel. Rolling out.",
                accent: accent
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Text("Multi-Drop")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                        PreviewPill(accent: accent)
                    }
                    Spacer()
                    Text(peers.isEmpty ? "No devices paired" : "Broadcast to \(peers.count) device\(peers.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                if peers.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accent)
                        Text("Pair a device to fill this grid")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PoofTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.08))
                    )
                } else {
                    let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(peers) { peer in
                            let online = session.isPeerOnline(peer.id)
                            HStack(spacing: 8) {
                                Image(systemName: online ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(online ? accent : PoofTheme.textTertiary)
                                Text(peer.name)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(PoofTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(accent.opacity(online ? 0.14 : 0.06))
                            )
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: PoofTheme.radiusMd)
        }
        .buttonStyle(.plain)
    }

    private func cliCard(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.361, blue: 0.322)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1.0, green: 0.749, blue: 0.235)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.239, green: 0.816, blue: 0.404)).frame(width: 8, height: 8)
                Spacer()
                Text("CLI · Preview")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                Text(cliCommand)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(PoofTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = cliCommand
                    session.toast = "Command copied"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PoofTheme.radiusMd, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PoofTheme.radiusMd)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            previewFeature = FeaturePreview(
                icon: "terminal.fill",
                title: "Poof CLI",
                tagline: "Scriptable transfers from your terminal",
                status: .comingSoon,
                description: "`poof send`, `poof pair`, `poof receive`. Ship files from CI jobs, cron tasks, or your build pipeline. Same E2E encryption, zero cloud.",
                accent: accent
            )
        }
    }

    private func apiKeyCard(accent: Color) -> some View {
        Button {
            previewFeature = FeaturePreview(
                icon: "key.fill",
                title: "API key",
                tagline: "Programmatic access to Poof transfers",
                status: .comingSoon,
                description: "Generate keys for scripts, servers, and integrations. Rate-limited, revocable, scoped. Everything stays peer-to-peer — the key just authenticates you.",
                accent: accent
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("API key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                        PreviewPill(accent: accent)
                    }
                    Text("pk_live_••••••4d92")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: PoofTheme.radiusMd)
        }
        .buttonStyle(.plain)
    }

    private func airGapCard(accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: airGapped ? "airplane" : "wifi")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(airGapped ? accent : PoofTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill((airGapped ? accent : Color.white).opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Air-gapped mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    PreviewPill(accent: accent)
                }
                Text(airGapped ? "LAN only · no internet" : "Internet enabled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $airGapped)
                .labelsHidden()
                .tint(accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
        .contentShape(Rectangle())
        .onTapGesture {
            previewFeature = FeaturePreview(
                icon: "airplane",
                title: "Air-gapped mode",
                tagline: "LAN-only transfers, zero internet",
                status: .comingSoon,
                description: "Force every transfer through your local network — no signaling server, no STUN, no cloud metadata. Perfect for sensitive environments.",
                accent: accent
            )
        }
    }
}
