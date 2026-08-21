import SwiftUI
import UIKit

// Business tier: local team management.
// Rename peer, change role (Admin/Member/Guest, on-device only), unpair.

struct TeamSheet: View {
    @EnvironmentObject private var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BusinessWorkspace.keyColor) private var color: String = BusinessWorkspace.defaultColor
    @State private var rolesTick = 0
    @State private var editingPeerId: String?
    @State private var editingName: String = ""
    var onOpenPairing: () -> Void = {}

    private var accent: Color {
        Color(hex: color) ?? PoofTier.business.accent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inviteBanner
                        if session.peers.peers.isEmpty {
                            empty
                        } else {
                            ForEach(session.peers.peers) { peer in
                                row(for: peer)
                            }
                        }
                    }
                    .padding(20)
                    .id(rolesTick)
                }
            }
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }

    private var inviteBanner: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onOpenPairing()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a teammate")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                    Text("Share a pair code from Settings")
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

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(PoofTheme.textTertiary)
            Text("No teammates yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PoofTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func row(for peer: PairedPeer) -> some View {
        let online = session.isPeerOnline(peer.id)
        let role = BusinessWorkspace.role(for: peer.id)
        let isEditing = editingPeerId == peer.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(online ? PoofTheme.green : PoofTheme.textTertiary)
                    .frame(width: 8, height: 8)
                if isEditing {
                    TextField(peer.name, text: $editingName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                    Button {
                        commitRename(for: peer)
                    } label: {
                        Text("Save").font(.system(size: 11, weight: .bold)).foregroundColor(accent)
                    }
                    Button {
                        editingPeerId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(PoofTheme.textTertiary)
                    }
                } else {
                    Text(peer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .lineLimit(1)
                    Text("· \(peer.platform)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PoofTheme.textTertiary)
                    Spacer()
                    Button {
                        editingName = peer.name
                        editingPeerId = peer.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PoofTheme.textSecondary)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(BusinessWorkspace.roles, id: \.self) { r in
                    let selected = r == role
                    Button {
                        BusinessWorkspace.setRole(r, for: peer.id)
                        rolesTick &+= 1
                    } label: {
                        Text(r)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(selected ? .white : PoofTheme.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                Capsule().fill(selected ? accent : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    session.peers.remove(peer.id)
                    session.signaling.broadcastUnpair(peer.id)
                } label: {
                    Text("Unpair")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.danger)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            Capsule().fill(PoofTheme.danger.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private func commitRename(for peer: PairedPeer) {
        let t = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            session.peers.rename(peer.id, to: t)
        }
        editingPeerId = nil
    }
}
