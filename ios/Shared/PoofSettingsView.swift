import StoreKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// Sheet Settings — préférences globales fonctionnelles. Chaque toggle est
// persisté (AppStorage ou UserDefaults) et lu par le code concerné à runtime.
// Groupé par sections logiques : General / Transfers / Security / Devices /
// Account / Help / About.

struct PoofSettingsView: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profile = PoofProfileImage.shared

    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue
    @AppStorage("poof.notif.onReceive") private var notifOnReceive: Bool = true
    @AppStorage("poof.notif.onOpened") private var notifOnOpened: Bool = true
    @AppStorage("poof.autoSavePhotos") private var autoSavePhotos: Bool = false
    @AppStorage("poof.confirmBeforeAccept") private var confirmBeforeAccept: Bool = false
    @AppStorage("poof.defaultCompression") private var defaultCompression: Bool = false
    @AppStorage("poof.defaultNotifyOnOpen") private var defaultNotifyOnOpen: Bool = false
    @AppStorage("poof.requireFaceIDForSecure") private var requireFaceIDSecure: Bool = true
    @AppStorage("poof.blockScreenshots") private var blockScreenshots: Bool = false
    @AppStorage("poof.haptics.enabled") private var hapticsEnabled: Bool = true

    @State private var showManageSubscription = false
    @State private var showResetConfirm = false
    @State private var showAdminInbox = false
    @State private var adminUnlocked = false

    private var tier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        notificationsSection
                        receiveSection
                        sendSection
                        securitySection
                        accountSection
                        helpSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .confirmationDialog(
            "Reset all Poof data ?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes paired devices, received files, custom photo, Apple ID link, and preferences. Irreversible.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications") {
            SettingsToggleRow(
                icon: "tray.and.arrow.down.fill",
                title: "New file received",
                subtitle: "Notifier quand un fichier arrive.",
                isOn: $notifOnReceive
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsToggleRow(
                icon: "eye.fill",
                title: "File opened",
                subtitle: "Notify when a recipient opens a file sent with Track.",
                isOn: $notifOnOpened
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsButtonRow(icon: "gear", title: "System notifications", trailing: "Open") {
                openSystemNotificationSettings()
            }
        }
    }

    // MARK: - Receive

    private var receiveSection: some View {
        SettingsSection(title: "Receive") {
            SettingsToggleRow(
                icon: "photo.stack.fill",
                title: "Auto-save Photos to library",
                subtitle: "Received photos and videos auto-copied to the gallery.",
                isOn: $autoSavePhotos
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsToggleRow(
                icon: "hand.raised.fill",
                title: "Ask before accepting",
                subtitle: "Ask for confirmation before any incoming download.",
                isOn: $confirmBeforeAccept
            )
        }
    }

    // MARK: - Send

    private var sendSection: some View {
        SettingsSection(title: "Send defaults") {
            SettingsToggleRow(
                icon: "bolt.fill",
                title: "Compress by default",
                subtitle: tier.isPremium ? "Apply Boost / LZFSE on every send." : "Requires Poof Premium.",
                isOn: Binding(
                    get: { defaultCompression && tier.isPremium },
                    set: { defaultCompression = $0 && tier.isPremium }
                ),
                disabled: !tier.isPremium
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsToggleRow(
                icon: "eyes",
                title: "Notify me on open",
                subtitle: tier
                    .isPremium ? "Enable Track by default to know who opens your sends." :
                    "Requires Poof Premium.",
                isOn: Binding(
                    get: { defaultNotifyOnOpen && tier.isPremium },
                    set: { defaultNotifyOnOpen = $0 && tier.isPremium }
                ),
                disabled: !tier.isPremium
            )
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        SettingsSection(title: "Security & Privacy") {
            SettingsToggleRow(
                icon: "faceid",
                title: "Face ID for Secure files",
                subtitle: "Biometrics required to open a Secure file received.",
                isOn: $requireFaceIDSecure
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsToggleRow(
                icon: "camera.metering.spot",
                title: "Block screenshots",
                subtitle: "Black screen in a screenshot taken during preview.",
                isOn: $blockScreenshots
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsToggleRow(
                icon: "waveform",
                title: "Haptics",
                subtitle: "Haptic vibrations on send and receive.",
                isOn: $hapticsEnabled
            )
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection(title: "Account") {
            SettingsRow(icon: "crown.fill", title: "Plan", trailingText: tier.isPremium ? "Premium" : "Free")
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsButtonRow(icon: "creditcard.fill", title: "Manage subscription", trailing: "Open") {
                showManageSubscription = true
            }
            #if canImport(UIKit) && os(iOS)
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            #endif
            if profile.isSignedIn {
                Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
                SettingsButtonRow(
                    icon: "person.crop.circle.badge.xmark",
                    title: "Sign out Apple ID",
                    trailing: "Sign out"
                ) {
                    profile.signOutApple()
                }
            }
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsButtonRow(icon: "trash.fill", title: "Reset all data", trailing: "Reset", destructive: true) {
                showResetConfirm = true
            }
            if adminUnlocked {
                Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
                SettingsButtonRow(icon: "tray.full.fill", title: "Admin inbox", trailing: "Open") {
                    showAdminInbox = true
                }
                .sheet(isPresented: $showAdminInbox) {
                    PoofAdminInbox()
                }
            }
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        SettingsSection(title: "Help & About") {
            SettingsLinkRow(
                icon: "envelope.fill",
                title: "Contact support",
                url: URL(string: "mailto:hello@poof.app?subject=Poof%20\(appVersion)")!
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsButtonRow(icon: "star.fill", title: "Rate Poof", trailing: nil) {
                requestAppStoreReview()
            }
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsLinkRow(
                icon: "hand.raised.fill",
                title: "Privacy Policy",
                url: URL(string: "https://poof.app/privacy")!
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsLinkRow(
                icon: "doc.text.fill",
                title: "Terms of Service",
                url: URL(string: "https://poof.app/terms")!
            )
            Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 60)
            SettingsRow(icon: "info.circle.fill", title: "Version", trailingText: appVersion)
                .onLongPressGesture(minimumDuration: 1.2) {
                    // Long-press 1.2s sur "Version" révèle le row "Admin inbox"
                    // dans Account. Raccourci secret pour toi (Poof team).
                    adminUnlocked.toggle()
                    PoofHaptics.success()
                }
        }
    }

    // MARK: - Actions

    private func openSystemNotificationSettings() {
        #if canImport(UIKit) && !os(watchOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        #elseif canImport(AppKit)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }

    private func requestAppStoreReview() {
        #if canImport(UIKit) && !os(watchOS)
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
            {
                SKStoreReviewController.requestReview(in: scene)
            }
        #elseif canImport(AppKit)
            if let url = URL(string: "macappstore://apps.apple.com/app/idPLACEHOLDER?action=write-review") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }

    private func resetAllData() {
        session.leaveSession()
        session.receivedFiles.removeAll()
        session.sentFiles.removeAll()
        profile.setCustomImage(nil)
        profile.signOutApple()
        profile.displayName = ""
        // Reset des toggles utilisateur.
        for key in [
            "poof.haptics.enabled", "poof.sounds.enabled", "poof.autoSavePhotos",
            "poof.defaultCompression", "poof.requireFaceIDForSecure",
            "poof.blockScreenshots", "poof.universalClipboard", "poof.hasOnboarded"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        dismiss()
    }
}

// MARK: - Section wrapper

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.6)
                .padding(.leading, 14)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
            )
        }
    }
}

// MARK: - Row primitives

private struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var trailingText: String?

    var body: some View {
        rowBase(icon: icon, title: title, subtitle: subtitle) {
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        rowBase(icon: icon, title: title, subtitle: subtitle, dim: disabled) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.white)
                .disabled(disabled)
        }
    }
}

private struct SettingsButtonRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var trailing: String?
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            rowBase(icon: icon, title: title, subtitle: subtitle, tint: destructive ? .red : .white) {
                HStack(spacing: 4) {
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(destructive ? .red.opacity(0.85) : .white.opacity(0.70))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            rowBase(icon: icon, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }
}

// MARK: - Shared row layout

private func rowBase(
    icon: String,
    title: String,
    subtitle: String? = nil,
    tint: Color = .white,
    dim: Bool = false,
    @ViewBuilder trailing: () -> some View
) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.15)))

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Spacer()

        trailing()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .opacity(dim ? 0.5 : 1)
    .contentShape(Rectangle())
}

#Preview {
    PoofSettingsView()
        .environmentObject(PoofSession())
}
