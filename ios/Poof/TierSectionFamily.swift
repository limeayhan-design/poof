import SwiftUI

// Family home section — "Family Room".
// Shown above the drop zone when tier == .family.
// Real data: session.peers.peers as family members, session.receivedFiles as recent shares.

struct TierSectionFamily: View {
    @EnvironmentObject private var session: PoofSession
    @AppStorage(KidControls.keyEnabled) private var kidEnabled: Bool = false
    @State private var previewFeature: FeaturePreview?

    var onOpenAddDevice: () -> Void = {}
    var onFamilyDrop: () -> Void = {}
    var onOpenKidControls: () -> Void = {}

    private let familyColors: [Color] = [
        Color(red: 1.0, green: 0.478, blue: 0.612),
        Color(red: 0.357, green: 0.545, blue: 1.0),
        Color(red: 0.545, green: 0.494, blue: 1.0),
        Color(red: 0.247, green: 0.749, blue: 0.498),
        Color(red: 1.0, green: 0.749, blue: 0.235)
    ]

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters.uppercased()
    }

    private func relative(_ date: Date) -> String {
        let s = -Int(date.timeIntervalSinceNow)
        if s < 60 {
            return "just now"
        }
        if s < 3600 {
            return "\(s / 60)m ago"
        }
        if s < 86400 {
            return "\(s / 3600)h ago"
        }
        return "\(s / 86400)d ago"
    }

    var body: some View {
        let accent = PoofTier.family.accent
        let peers = session.peers.peers
        let onlineCount = peers.filter { session.isPeerOnline($0.id) }.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent)
                Text("Family Room")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                if peers.isEmpty {
                    Text("Empty")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PoofTheme.textTertiary)
                } else {
                    Text("\(onlineCount) online")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                }
            }

            if peers.isEmpty {
                inviteFamilyCard(accent: accent)
            } else {
                membersStrip(peers: peers, accent: accent)
            }

            if !session.receivedFiles.isEmpty {
                recentSharesFeed(files: Array(session.receivedFiles.prefix(2)), accent: accent)
            }

            familyDropCard(accent: accent, hasPeers: !peers.isEmpty)

            kidControlsButton(accent: accent)
        }
        .sheet(item: $previewFeature) { FeaturePreviewSheet(preview: $0) }
    }

    private func inviteFamilyCard(accent: Color) -> some View {
        Button {
            onOpenAddDevice()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite your family")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Text("Pair the first device to get started")
                        .font(.system(size: 11, weight: .medium))
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

    private func membersStrip(peers: [PairedPeer], accent _: Color) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(peers.enumerated()), id: \.element.id) { idx, peer in
                let color = familyColors[idx % familyColors.count]
                let online = session.isPeerOnline(peer.id)
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(color.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(initials(from: peer.name))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        Circle().fill(online ? PoofTheme.green : PoofTheme.textTertiary)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(PoofTheme.bgBase, lineWidth: 2))
                    }
                    Text(peer.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private func recentSharesFeed(files: [PoofSession.ReceivedFile], accent: Color) -> some View {
        VStack(spacing: 6) {
            ForEach(files) { file in
                HStack(spacing: 10) {
                    Image(systemName: iconForFile(file.name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                            .lineLimit(1)
                        Text(relative(file.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PoofTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: PoofTheme.radiusSm)
            }
        }
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mov", "mp4", "m4v": return "film.fill"
        case "pdf": return "doc.text.fill"
        case "zip", "rar", "7z": return "archivebox.fill"
        case "mp3", "m4a", "wav": return "music.note"
        default: return "doc.fill"
        }
    }

    private func familyDropCard(accent: Color, hasPeers: Bool) -> some View {
        Button {
            if hasPeers {
                onFamilyDrop()
            } else {
                onOpenAddDevice()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [accent, PoofTier.family.glow],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop for family")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Text(hasPeers ? "Everyone receives instantly" : "Pair a device to enable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: PoofTheme.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: PoofTheme.radiusMd)
                    .strokeBorder(accent.opacity(hasPeers ? 0.35 : 0.15), lineWidth: 1)
            )
            .opacity(hasPeers ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
    }

    private func kidControlsButton(accent: Color) -> some View {
        Button {
            onOpenKidControls()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kidEnabled ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(kidEnabled ? accent : PoofTheme.textSecondary)
                Text("Kid controls")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(kidEnabled ? "On" : "Off")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(kidEnabled ? accent : PoofTheme.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill((kidEnabled ? accent : PoofTheme.textTertiary).opacity(0.14)))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            .foregroundColor(PoofTheme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassCard(radius: PoofTheme.radiusSm)
        }
        .buttonStyle(.plain)
    }
}
