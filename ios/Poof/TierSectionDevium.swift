import SwiftUI
import UIKit

// Devium home section — "Dev cockpit".
// Shown above the drop zone when tier == .devium.
// Real data: session.peers.peers as Multi-Drop targets, real device name in CLI.

struct TierSectionDevium: View {
    @EnvironmentObject private var session: PoofSession
    @AppStorage(AirGap.keyEnabled) private var airGapped: Bool = false
    @State private var previewFeature: FeaturePreview?
    @State private var showDebugConsole = false
    @State private var showSelfHost = false

    var onMultiDrop: () -> Void = {}

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

            debugConsoleCard(accent: accent)

            selfHostCard(accent: accent)

            airGapCard(accent: accent)
        }
        .sheet(item: $previewFeature) { FeaturePreviewSheet(preview: $0) }
        .sheet(isPresented: $showDebugConsole) {
            DebugConsoleSheet().environmentObject(session)
        }
        .sheet(isPresented: $showSelfHost) {
            SelfHostSignalingSheet().environmentObject(session)
        }
    }

    private func multiDropCard(peers: [PairedPeer], accent: Color) -> some View {
        let onlineCount = peers.filter { session.isPeerOnline($0.id) }.count
        return Button {
            if peers.isEmpty {
                previewFeature = FeaturePreview(
                    icon: "square.grid.2x2.fill",
                    title: "Multi-Drop",
                    tagline: "Broadcast a file to N devices at once",
                    status: .available,
                    description: "Pair a few devices from the gear menu, then send one file to all of them in a single tap. WebRTC peer-to-peer, no cloud relay.",
                    accent: accent
                )
            } else {
                onMultiDrop()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Multi-Drop")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Spacer()
                    Text(peers.isEmpty
                        ? "No devices paired"
                        : "Broadcast to \(onlineCount)/\(peers.count) online")
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

    private func debugConsoleCard(accent: Color) -> some View {
        Button {
            showDebugConsole = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1.0, green: 0.361, blue: 0.322)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 1.0, green: 0.749, blue: 0.235)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 0.239, green: 0.816, blue: 0.404)).frame(width: 8, height: 8)
                    Spacer()
                    Text("Debug console")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                HStack(alignment: .center, spacing: 8) {
                    Circle().fill(session.isRTCConnected ? PoofTheme.green : PoofTheme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(session.connectionState)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PoofTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(session.onlinePeerIds.count) online")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
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
        }
        .buttonStyle(.plain)
    }

    private func selfHostCard(accent: Color) -> some View {
        Button {
            showSelfHost = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Self-hosted signaling")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Text(PoofSession.signalingURL.absoluteString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(PoofTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        let signalingIsLAN = AirGap.isLAN(PoofSession.signalingURL)
        return HStack(spacing: 12) {
            Image(systemName: airGapped ? "airplane" : "wifi")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(airGapped ? accent : PoofTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill((airGapped ? accent : Color.white).opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Air-gapped mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                Text(airGapped
                    ? (signalingIsLAN ? "LAN only · no internet" : "LAN only · signaling server is not LAN")
                    : "Internet enabled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(airGapped && !signalingIsLAN ? PoofTheme.accent2 : PoofTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $airGapped)
                .labelsHidden()
                .tint(accent)
                .onChange(of: airGapped) { _, on in
                    session.applyAirGap(on)
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }
}
