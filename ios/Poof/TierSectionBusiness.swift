import SwiftUI
import UIKit

// Business home section — "Team command".
// Shown above the drop zone when tier == .business.
// Real data: session.peers.peers as team, session.receivedFiles as audit stream.

struct TierSectionBusiness: View {
    @EnvironmentObject private var session: PoofSession
    @State private var previewFeature: FeaturePreview?

    private let memberColors: [Color] = [
        Color(red: 0.561, green: 0.639, blue: 0.710),
        Color(red: 0.357, green: 0.545, blue: 1.0),
        Color(red: 0.545, green: 0.494, blue: 1.0),
        Color(red: 0.247, green: 0.749, blue: 0.498),
        Color(red: 1.0,   green: 0.478, blue: 0.612)
    ]

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters.uppercased()
    }

    private func role(for index: Int, total: Int) -> String {
        if index == 0 { return "Admin" }
        if index == total - 1 && total > 2 { return "Guest" }
        return "Member"
    }

    private func relative(_ date: Date) -> String {
        let s = -Int(date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    private var workspaceName: String {
        let device = UIDevice.current.name
        return "\(device)'s workspace"
    }

    var body: some View {
        let accent = PoofTier.business.accent
        let glow = PoofTier.business.glow
        let peers = session.peers.peers
        let memberCount = peers.count + 1 // +1 for the current device

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent)
                Text("Team command")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(session.isSignalingConnected ? PoofTheme.green : PoofTheme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(session.isSignalingConnected ? "Online" : "Offline")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PoofTheme.textSecondary)
                }
            }

            orgHeader(accent: accent, glow: glow, memberCount: memberCount)

            auditCard(accent: accent)

            teamStrip(peers: peers, accent: accent)

            brandingCard(accent: accent)
        }
        .sheet(item: $previewFeature) { FeaturePreviewSheet(preview: $0) }
    }

    private func orgHeader(accent: Color, glow: Color, memberCount: Int) -> some View {
        Button {
            previewFeature = FeaturePreview(
                icon: "building.2.fill",
                title: "Workspace",
                tagline: "Rename, invite, and manage",
                status: .comingSoon,
                description: "Create a shared organization name, invite teammates by email or link, and assign roles. All transfers stay peer-to-peer — the workspace is just identity.",
                accent: accent
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, glow],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text("P")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(workspaceName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PoofTheme.textPrimary)
                            .lineLimit(1)
                        PreviewPill(accent: accent)
                    }
                    Text("\(memberCount) member\(memberCount == 1 ? "" : "s") · Enterprise plan")
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
        }
        .buttonStyle(.plain)
    }

    private func auditCard(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                Text("Live audit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                Circle().fill(session.isSignalingConnected ? PoofTheme.green : PoofTheme.textTertiary)
                    .frame(width: 6, height: 6)
            }
            if session.receivedFiles.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PoofTheme.textTertiary)
                    Text("No activity yet — your transfers appear here in real time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.receivedFiles.prefix(3)) { file in
                        HStack(spacing: 8) {
                            Circle().fill(accent.opacity(0.7)).frame(width: 5, height: 5)
                            Text("Received \(file.name)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(PoofTheme.textPrimary.opacity(0.86))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(relative(file.date))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(PoofTheme.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
        .contentShape(Rectangle())
        .onTapGesture {
            previewFeature = FeaturePreview(
                icon: "doc.text.magnifyingglass",
                title: "Live audit",
                tagline: "Every transfer, every device, real time",
                status: session.receivedFiles.isEmpty ? .available : .available,
                description: "Track file sends, receives, and device pairings across your team as they happen. Export to CSV for compliance. On-device — nothing shared with us.",
                accent: accent
            )
        }
    }

    private func teamStrip(peers: [PairedPeer], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Team")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                Button {
                    previewFeature = FeaturePreview(
                        icon: "person.2.fill",
                        title: "Team management",
                        tagline: "Invite, revoke, assign roles",
                        status: .comingSoon,
                        description: "Bulk invite by email, set per-user roles (Admin/Member/Guest), revoke access instantly. All identity flows through your workspace.",
                        accent: accent
                    )
                } label: {
                    Text("Manage")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accent)
                }
                .buttonStyle(.plain)
            }
            if peers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                    Text("Invite your first teammate")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PoofTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.08))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Current device (Admin)
                        memberBubble(
                            initials: initials(from: UIDevice.current.name),
                            role: "You · Admin",
                            color: memberColors[0],
                            online: true
                        )
                        ForEach(Array(peers.enumerated()), id: \.element.id) { idx, peer in
                            let color = memberColors[(idx + 1) % memberColors.count]
                            let online = session.isPeerOnline(peer.id)
                            memberBubble(
                                initials: initials(from: peer.name),
                                role: role(for: idx + 1, total: peers.count + 1),
                                color: color,
                                online: online
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private func memberBubble(initials: String, role: String, color: Color, online: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(color.opacity(0.9))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
                Circle().fill(online ? PoofTheme.green : PoofTheme.textTertiary)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(PoofTheme.bgBase, lineWidth: 2))
            }
            Text(role)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(PoofTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 60)
    }

    private func brandingCard(accent: Color) -> some View {
        Button {
            previewFeature = FeaturePreview(
                icon: "paintpalette.fill",
                title: "Custom branding",
                tagline: "Your logo, your colors, your domain",
                status: .comingSoon,
                description: "White-label the send/receive UI with your company logo and colors. Route transfers through your own custom domain. Enterprise-only.",
                accent: accent
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Custom branding")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textPrimary)
                        PreviewPill(accent: accent)
                    }
                    Text("Your logo · your colors · your domain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: PoofTheme.radiusMd)
        }
        .buttonStyle(.plain)
    }
}
