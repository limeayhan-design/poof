import SwiftUI

// Premium home section — "Power tools".
// Shown above the drop zone when tier == .premium.
// Universal Clipboard is wired to session.pushClipboard().
// Other tiles open FeaturePreviewSheet with honest status.

struct TierSectionPremium: View {
    @EnvironmentObject private var session: PoofSession
    @State private var previewFeature: FeaturePreview?
    @State private var showRemoteFiles = false
    @State private var showScreenMirror = false
    @State private var showScreenViewer = false
    var onOpenFolderPicker: (() -> Void)? = nil

    var body: some View {
        let accent = PoofTier.premium.accent

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent)
                Text("Power tools")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                Text("Premium")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
            }

            // Universal Clipboard — WIRED. Handles text + image (Premium).
            Button {
                if session.isRTCConnected {
                    if let summary = session.pushClipboardRich() {
                        session.toast = summary
                    } else {
                        session.toast = "Clipboard is empty"
                    }
                } else {
                    previewFeature = FeaturePreview(
                        icon: "doc.on.clipboard.fill",
                        title: "Universal Clipboard",
                        tagline: "Copy anywhere, paste everywhere",
                        status: .available,
                        description: "Copy text or an image, then tap this tile — Poof pushes it to your paired device instantly. Connect a device from the gear icon to enable it.",
                        accent: accent
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Universal Clipboard")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(PoofTheme.textPrimary)
                            Circle().fill(session.isRTCConnected ? PoofTheme.green : PoofTheme.textTertiary)
                                .frame(width: 6, height: 6)
                            Text(session.isRTCConnected ? "Ready · tap to push" : "Waiting")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(PoofTheme.textSecondary)
                        }
                        Text("Text, images, and files across every device")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PoofTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(session.isRTCConnected ? accent : PoofTheme.textTertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: PoofTheme.radiusMd)
            }
            .buttonStyle(.plain)

            // 2x2 grid of feature tiles — each opens a preview sheet
            HStack(spacing: 10) {
                powerTile(icon: "folder.fill", title: "Folder Drop", subtitle: "Any size", status: .available, accent: accent) {
                    if let onOpenFolderPicker {
                        onOpenFolderPicker()
                    } else {
                        previewFeature = FeaturePreview(
                            icon: "folder.fill",
                            title: "Folder Drop",
                            tagline: "Send an entire folder in one drop",
                            status: .available,
                            description: "Pick a folder from Files. Poof enumerates every file inside and sends them one after the other, keeping the structure intact.",
                            accent: accent
                        )
                    }
                }
                powerTile(icon: "rectangle.on.rectangle", title: "Screen Mirror", subtitle: session.screenBroadcast.isBroadcasting ? "Live · tap to stop" : "1-tap to any device", status: .available, accent: accent) {
                    if session.isRTCConnected {
                        showScreenMirror = true
                    } else {
                        previewFeature = FeaturePreview(
                            icon: "rectangle.on.rectangle",
                            title: "Screen Mirror",
                            tagline: "Cast your screen anywhere",
                            status: .available,
                            description: "Push your iPhone screen to a paired device at ~10 FPS. Fully P2P — the frames flow through the encrypted WebRTC link, never a server. Connect a device first, then reopen this tile.",
                            accent: accent
                        )
                    }
                }
            }
            HStack(spacing: 10) {
                powerTile(icon: "externaldrive.connected.to.line.below.fill", title: "Remote Files", subtitle: "Browse peer", status: .available, accent: accent) {
                    showRemoteFiles = true
                }
                powerTile(icon: "eye.fill", title: "Read receipts", subtitle: "Sent · Delivered · Seen", status: .available, accent: accent) {
                    previewFeature = FeaturePreview(
                        icon: "eye.fill",
                        title: "Read receipts",
                        tagline: "Know when your file lands",
                        status: .available,
                        description: "Every file you send now shows a receipt in History: Sent when it left this device, Delivered when the peer wrote it to disk, Seen when the peer opened the preview. Fully P2P — nothing leaves the encrypted link.",
                        accent: accent
                    )
                }
            }
        }
        .sheet(item: $previewFeature) { FeaturePreviewSheet(preview: $0) }
        .sheet(isPresented: $showRemoteFiles) {
            RemoteFilesSheet().environmentObject(session)
        }
        .sheet(isPresented: $showScreenMirror) {
            ScreenMirrorSenderSheet().environmentObject(session)
        }
        .fullScreenCover(isPresented: $showScreenViewer) {
            ScreenMirrorReceiverSheet().environmentObject(session)
        }
        .onChange(of: session.screenBroadcast.isReceiving) { _, receiving in
            if receiving && !showScreenViewer { showScreenViewer = true }
            if !receiving && showScreenViewer { showScreenViewer = false }
        }
    }

    private func powerTile(icon: String, title: String, subtitle: String, status: FeatureStatus, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                            .lineLimit(1)
                        if status != .available {
                            Circle().fill(status.color).frame(width: 4, height: 4)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .glassCard(radius: PoofTheme.radiusMd)
        }
        .buttonStyle(.plain)
    }
}
