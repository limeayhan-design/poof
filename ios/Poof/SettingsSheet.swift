import SwiftUI
import UIKit

// Settings sheet — présenté depuis le bouton avatar du CustomHeader (Send tab).
// Regroupe: identité appareil, abonnement, légal, about.
// Style Ripples (fond noir + cards white-opacity) pour cohérence avec le paywall.

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue

    @State private var deviceName: String = PoofDeviceIdentity.name
    @State private var showRestoreAlert = false

    private var currentTier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    // Placeholders — à remplacer avant submit App Store.
    private let privacyURL = URL(string: "https://poof.app/privacy")!
    private let termsURL = URL(string: "https://poof.app/terms")!
    private let supportEmail = "hello@poof.app"
    private let appStoreId = "0000000000"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RipplesTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    deviceSection
                    subscriptionSection
                    legalSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }

            RipplesHeaderButton(systemName: "xmark") {
                commitDeviceName()
                dismiss()
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .alert("Not available yet", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In-app purchases will be enabled at launch.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Settings")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Text("Your device, your plan, your privacy.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.bottom, 4)
    }

    // MARK: - Device

    private var deviceSection: some View {
        section(title: "Device") {
            VStack(spacing: 0) {
                deviceNameRow
                divider
                infoRow(label: "Device ID", value: shortDeviceId)
            }
        }
    }

    private var deviceNameRow: some View {
        HStack(spacing: 12) {
            Text("Name")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 90, alignment: .leading)
            TextField("", text: $deviceName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { commitDeviceName() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var shortDeviceId: String {
        String(PoofDeviceIdentity.deviceId.prefix(8)).uppercased()
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        section(title: "Subscription") {
            VStack(spacing: 0) {
                infoRow(
                    label: "Current plan",
                    value: currentTier.displayName,
                    valueColor: currentTier.isPremium ? RipplesTokens.violetAccent : .white
                )
                divider
                tapRow(label: "Manage plan", trailing: "chevron.right") {
                    dismiss()
                    NotificationCenter.default.post(name: .poofOpenPricing, object: nil)
                }
                divider
                tapRow(label: "Restore purchases", trailing: "arrow.clockwise") {
                    PoofHaptics.tap()
                    showRestoreAlert = true
                }
            }
        }
    }

    // MARK: - Legal & Support

    private var legalSection: some View {
        section(title: "Legal & Support") {
            VStack(spacing: 0) {
                linkRow(label: "Privacy Policy", url: privacyURL)
                divider
                linkRow(label: "Terms of Service", url: termsURL)
                divider
                mailRow(label: "Contact Support", email: supportEmail)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section(title: "About") {
            VStack(spacing: 0) {
                infoRow(label: "Version", value: appVersion)
                divider
                tapRow(label: "Rate Poof on the App Store", trailing: "star.fill") {
                    PoofHaptics.tap()
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreId)?action=write-review") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - Building blocks

    private func section(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 4)
            content()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private func infoRow(
        label: String,
        value: String,
        valueColor: Color = .white
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func tapRow(
        label: String,
        trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func linkRow(label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private func mailRow(label: String, email: String) -> some View {
        let url = URL(string: "mailto:\(email)") ?? privacyURL
        return Link(destination: url) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(email)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - Actions

    private func commitDeviceName() {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deviceName = PoofDeviceIdentity.suggestedName
            return
        }
        if trimmed != PoofDeviceIdentity.name {
            PoofDeviceIdentity.name = trimmed
        }
    }
}
