import SwiftUI
import UIKit

// Devium: live WebRTC + signaling inspector.
// Every value here is real session state, updated in real time.

struct DebugConsoleSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AirGap.keyEnabled) private var airGapped: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        signalingBlock
                        rtcBlock
                        peersBlock
                        deviceBlock
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Debug console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(PoofTier.devium.accent)
                }
            }
        }
    }

    // MARK: - Header (three traffic-light dots + subtitle)

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.361, blue: 0.322)).frame(width: 10, height: 10)
            Circle().fill(Color(red: 1.0, green: 0.749, blue: 0.235)).frame(width: 10, height: 10)
            Circle().fill(Color(red: 0.239, green: 0.816, blue: 0.404)).frame(width: 10, height: 10)
            Spacer()
            Text("live · updates as events fire")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PoofTheme.radiusMd, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PoofTheme.radiusMd)
                .strokeBorder(PoofTier.devium.accent.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Signaling

    private var signalingBlock: some View {
        let up = session.isSignalingConnected
        let url = PoofSession.signalingURL.absoluteString
        return card(title: "Signaling") {
            row(
                icon: up ? "checkmark.circle.fill" : "xmark.circle.fill",
                iconColor: up ? PoofTheme.green : PoofTheme.danger,
                label: "status",
                value: up ? "connected" : "disconnected"
            )
            row(
                icon: "link",
                iconColor: PoofTheme.textSecondary,
                label: "url",
                value: url,
                copyable: true
            )
            row(
                icon: airGapped ? "airplane" : "wifi",
                iconColor: airGapped ? PoofTier.devium.accent : PoofTheme.textSecondary,
                label: "air-gap",
                value: airGapped ? "on · LAN only" : "off"
            )
        }
    }

    // MARK: - WebRTC

    private var rtcBlock: some View {
        card(title: "WebRTC") {
            row(
                icon: session.isRTCConnected ? "dot.radiowaves.left.and.right" : "circle",
                iconColor: session.isRTCConnected ? PoofTheme.green : PoofTheme.textTertiary,
                label: "state",
                value: session.connectionState
            )
            row(
                icon: "person.fill",
                iconColor: PoofTheme.textSecondary,
                label: "active peer",
                value: session.activePeerId ?? "—",
                copyable: session.activePeerId != nil
            )
        }
    }

    // MARK: - Peers

    private var peersBlock: some View {
        let paired = session.peers.peers
        return card(title: "Peers · \(session.onlinePeerIds.count)/\(paired.count) online") {
            if paired.isEmpty {
                Text("No paired devices.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PoofTheme.textTertiary)
            } else {
                ForEach(paired) { p in
                    let online = session.onlinePeerIds.contains(p.id)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(online ? PoofTheme.green : PoofTheme.textTertiary)
                            .frame(width: 8, height: 8)
                        Text(p.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                        Spacer()
                        Text(p.id)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(PoofTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            UIPasteboard.general.string = p.id
                            session.toast = "Copied peer id"
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(PoofTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device

    private var deviceBlock: some View {
        card(title: "This device") {
            row(
                icon: "iphone",
                iconColor: PoofTheme.textSecondary,
                label: "name",
                value: PoofDeviceIdentity.name,
                copyable: true
            )
            row(
                icon: "number",
                iconColor: PoofTheme.textSecondary,
                label: "id",
                value: PoofDeviceIdentity.deviceId,
                copyable: true
            )
            row(
                icon: "cpu",
                iconColor: PoofTheme.textSecondary,
                label: "platform",
                value: PoofDeviceIdentity.platform
            )
        }
    }

    // MARK: - Helpers

    private func card(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
                .kerning(0.6)
            VStack(spacing: 8) { content() }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private func row(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        copyable: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    session.toast = "Copied"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.textSecondary)
                }
            }
        }
    }
}
