import SwiftUI
import UIKit

// Devium: point Poof at your own signaling server.
// Runs the same public docker image (see repo README). LAN-only when Air-gap is on.

struct SelfHostSignalingSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AirGap.keyEnabled) private var airGapped: Bool = false
    @State private var urlField: String = PoofSession.signalingURL.absoluteString
    @State private var errorMsg: String?

    private let defaultURL = "https://poof-signal.fly.dev"

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        editor
                        actions
                        howTo
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Self-hosted signaling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(PoofTier.devium.accent)
                }
            }
        }
    }

    // MARK: - Blocks

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PoofTier.devium.accent)
                Text("Own your signaling")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
            }
            Text(
                "Signaling is only used to introduce peers. Files always travel P2P over WebRTC — never through this server."
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(PoofTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIGNALING URL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
                .kerning(0.6)
            TextField("", text: $urlField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusSm, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusSm)
                        .strokeBorder(PoofTheme.glassStroke, lineWidth: 1)
                )
            if let msg = errorMsg {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PoofTheme.accent2)
                    Text(msg)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.accent2)
                }
            } else if airGapped {
                HStack(spacing: 6) {
                    Image(systemName: "airplane")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PoofTier.devium.accent)
                    Text("Air-gap is on — only LAN URLs will be accepted.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PoofTheme.textSecondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Save & reconnect")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusSm, style: .continuous)
                        .fill(PoofTier.devium.accent)
                )
            }
            .buttonStyle(.plain)
            Button {
                urlField = defaultURL
                errorMsg = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text("Reset")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(PoofTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassCard(radius: PoofTheme.radiusSm)
            }
            .buttonStyle(.plain)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUN YOUR OWN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PoofTheme.textTertiary)
                .kerning(0.6)
            snippet("docker run -p 3000:3000 ghcr.io/poof/signal:latest")
            Text("Then point this field at http://<host>:3000. Any device using the same URL will discover each other.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
    }

    private func snippet(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(PoofTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = text
                session.toast = "Copied"
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PoofTheme.textSecondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: PoofTheme.radiusSm, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }

    // MARK: - Save

    private func save() {
        let trimmed = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            errorMsg = "Invalid URL. Try https://your-host:3000"
            return
        }
        if airGapped, !AirGap.isLAN(url) {
            errorMsg = "Air-gap refuses non-LAN URLs. Turn off Air-gap or use a LAN host."
            return
        }
        errorMsg = nil
        session.updateSignalingURL(url)
        dismiss()
    }
}
