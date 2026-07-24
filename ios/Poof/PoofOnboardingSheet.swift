import SwiftUI

// First-launch onboarding — asks the user to set the signaling relay URL.
// Two paths: scan the QR from an already-paired device (contains host), or type it.

struct PoofOnboardingSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = PoofDeviceIdentity.name
    @State private var urlField: String = ""
    @State private var showScanner = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        heroBlock
                        nameBlock
                        Divider().background(PoofTheme.glassStroke)
                        relayBlock
                        Divider().background(PoofTheme.glassStroke)
                        continueButton
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
            .sheet(isPresented: $showScanner) {
                QRScannerView { raw in
                    showScanner = false
                    apply(scanned: raw)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Poof")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(PoofTheme.textPrimary)
            Text("Send anything to any device, instantly and privately.\nTwo quick steps to get started.")
                .font(.system(size: 14))
                .foregroundColor(PoofTheme.textSecondary)
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1. Name this device", systemImage: "1.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            TextField("Device name", text: $name)
                .font(.system(size: 15))
                .foregroundColor(PoofTheme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassCard()
        }
    }

    private var relayBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2. Point to your Poof relay", systemImage: "2.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            Text("Scan the QR shown on another Poof device, or type its address (e.g. http://192.168.1.42:3000).")
                .font(.system(size: 12))
                .foregroundColor(PoofTheme.textTertiary)

            Button {
                showScanner = true
            } label: {
                Label("Scan QR from another device", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(PoofTheme.accent))
            }

            HStack {
                Rectangle().fill(PoofTheme.glassStroke).frame(height: 1)
                Text("or").font(.system(size: 11)).foregroundColor(PoofTheme.textTertiary)
                Rectangle().fill(PoofTheme.glassStroke).frame(height: 1)
            }

            TextField("http://…", text: $urlField)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(PoofTheme.textPrimary)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassCard()

            if let err = errorText {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(PoofTheme.danger)
            }
        }
    }

    private var continueButton: some View {
        Button {
            saveAndDismiss()
        } label: {
            Text("Get started")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(canContinue ? PoofTheme.accent : PoofTheme.accent.opacity(0.4)))
        }
        .disabled(!canContinue)
        .buttonStyle(.plain)
    }

    private var canContinue: Bool {
        Self.parseURL(urlField) != nil
    }

    // MARK: - Actions

    private func apply(scanned raw: String) {
        if let host = Self.extractHost(from: raw) {
            urlField = host
            errorText = nil
        } else {
            errorText = "Couldn't read a URL from that QR."
        }
    }

    private func saveAndDismiss() {
        guard let url = Self.parseURL(urlField) else {
            errorText = "That doesn't look like a valid URL."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { PoofDeviceIdentity.name = trimmed }
        session.updateSignalingURL(url)
        session.completeOnboarding()
        dismiss()
    }

    // MARK: - Parsing

    static func parseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    static func extractHost(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let idx = trimmed.range(of: "/#") {
                return String(trimmed[..<idx.lowerBound])
            }
            if let idx = trimmed.range(of: "/", range: trimmed.index(trimmed.startIndex, offsetBy: 8)..<trimmed.endIndex) {
                return String(trimmed[..<idx.lowerBound])
            }
            return trimmed
        }
        return nil
    }
}
