import MultipeerConnectivity
import SwiftUI

/// Sheet plein écran ouverte au long-press sur le chip Offline. 3 toggles +
/// panneau de statut avec la liste des devices détectés à proximité.
struct OfflineConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: OfflineConfig
    @ObservedObject var offline: PoofOfflineManager
    /// Devices déjà paired via internet — l'utilisateur en coche 1 ou plusieurs
    /// pour dire « ceux-là, je veux pouvoir les joindre offline ». Seuls les
    /// devices avec un `peerId` stable sont proposés (les slots manuels legacy
    /// sans id sont exclus).
    var linkedDevices: [PairedDevice]
    var onApply: (OfflineConfig) -> Void

    @State private var draft: OfflineConfig

    init(
        config: Binding<OfflineConfig>,
        offline: PoofOfflineManager,
        linkedDevices: [PairedDevice],
        onApply: @escaping (OfflineConfig) -> Void
    ) {
        _config = config
        self.offline = offline
        self.linkedDevices = linkedDevices
        self.onApply = onApply
        _draft = State(initialValue: config.wrappedValue)
    }

    var body: some View {
        ZStack {
            background
            content
            topBar
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header
                advertiseRow
                wifiRow
                bluetoothRow
                linkedDevicesSection
                discoveryStatus
                applyButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 80)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Linked offline devices (pré-sélection multi)

    private var linkedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(L10n(fr: "Appareils liés offline", en: "Linked offline devices").localized)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
            }
            Text(L10n(
                fr: "Coche les appareils que tu veux pouvoir joindre sans internet. Quand tu passeras en Offline, seuls ceux-ci se connecteront automatiquement.",
                en: "Tick the devices you want to reach without internet. When you switch to Offline, only these will auto-connect."
            ).localized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if linkedDevices.isEmpty {
                Text(L10n(
                    fr: "Aucun appareil appairé pour l'instant. Appaire d'abord un appareil depuis l'écran Send.",
                    en: "No paired device yet. Pair a device first from the Send screen."
                ).localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                ForEach(linkedDevices, id: \.peerId) { device in
                    linkedDeviceRow(device)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func linkedDeviceRow(_ device: PairedDevice) -> some View {
        let id = device.peerId ?? ""
        let isOn = draft.linkedDeviceIds.contains(id)
        Button {
            guard !id.isEmpty else { return }
            PoofHaptics.tap()
            if isOn {
                draft.linkedDeviceIds.remove(id)
            } else {
                draft.linkedDeviceIds.insert(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: device.kind.sfSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name ?? device.kind.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(device.kind.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isOn ? .white : .white.opacity(0.45))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 68, height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                    )
                Image(systemName: "airplane")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n(fr: "Envoi Offline", en: "Offline send").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(L10n(
                fr: "Envoi pair-à-pair sans internet — Bluetooth ou Wi-Fi Direct, jusqu'à 100 m.",
                en: "Peer-to-peer send without internet — Bluetooth or Wi-Fi Direct, up to 100 m."
            ).localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Rows

    private var advertiseRow: some View {
        settingRow(
            icon: "dot.radiowaves.up.forward",
            title: L10n(fr: "Découvrable", en: "Discoverable").localized,
            subtitle: L10n(
                fr: "Rend cet appareil visible pour recevoir un envoi hors ligne.",
                en: "Makes this device visible to receive an offline send."
            ).localized,
            isOn: $draft.advertise
        )
    }

    private var wifiRow: some View {
        settingRow(
            icon: "wifi",
            title: L10n(fr: "Wi-Fi Direct", en: "Wi-Fi Direct").localized,
            subtitle: L10n(
                fr: "Débit élevé, portée ~100 m. Recommandé pour les gros fichiers.",
                en: "High throughput, ~100 m range. Best for large files."
            ).localized,
            isOn: $draft.allowWifi
        )
    }

    private var bluetoothRow: some View {
        settingRow(
            icon: "dot.radiowaves.left.and.right",
            title: L10n(fr: "Bluetooth", en: "Bluetooth").localized,
            subtitle: L10n(
                fr: "Portée ~10 m, plus lent. Utile quand le Wi-Fi est coupé.",
                en: "~10 m range, slower. Useful when Wi-Fi is off."
            ).localized,
            isOn: $draft.allowBluetooth
        )
    }

    // MARK: - Discovery status

    private var discoveryStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(L10n(fr: "Appareils à proximité", en: "Nearby devices").localized)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                if offline.isBrowsing {
                    ProgressView().tint(.white)
                }
            }
            if offline.discoveredPeers.isEmpty {
                Text(L10n(
                    fr: "Aucun appareil détecté pour l'instant. Assure-toi que l'autre appareil a Poof ouvert et mode Offline actif.",
                    en: "No devices found yet. Make sure the other device has Poof open with Offline mode enabled."
                ).localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(offline.discoveredPeers, id: \.hash) { peer in
                    HStack {
                        Image(systemName: "iphone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(peer.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        if offline.connectedPeers.contains(peer) {
                            Text(L10n(fr: "Connected", en: "Connected").localized)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white))
                        } else {
                            Button(L10n(fr: "Connecter", en: "Connect").localized) {
                                offline.invite(peer)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    // MARK: - Row helper

    private func settingRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private var applyButton: some View {
        Button {
            PoofHaptics.impactMedium()
            onApply(draft)
            dismiss()
        } label: {
            Text(L10n(fr: "Appliquer", en: "Apply").localized)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    PoofHaptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}
