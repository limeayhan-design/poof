import SwiftUI

/// Sheet plein écran ouverte au long-press sur le chip Boost du rectangle
/// Premium. 2 toggles simples : compression + broadcast.
struct BoostConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: BoostConfig
    var onApply: (BoostConfig) -> Void

    @State private var draft: BoostConfig

    init(config: Binding<BoostConfig>, onApply: @escaping (BoostConfig) -> Void) {
        _config = config
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
                compressionRow
                broadcastRow
                applyButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 80)
            .padding(.bottom, 32)
        }
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
                Image(systemName: "bolt.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n(fr: "Envoi Boost", en: "Boost send").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(L10n(
                fr: "Fichiers jusqu'à 50 Go, priorité serveurs et compression intelligente sans perte.",
                en: "Files up to 50 GB, server priority and smart lossless compression."
            ).localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 6)
    }

    private var compressionRow: some View {
        settingRow(
            icon: "square.and.arrow.down.on.square.fill",
            title: L10n(fr: "Compression sans perte", en: "Lossless compression").localized,
            subtitle: L10n(
                fr: "Réduit la taille jusqu'à 30 % avant envoi, sans altérer le fichier.",
                en: "Shrinks the file by up to 30% before send, no quality loss."
            ).localized,
            isOn: $draft.compression
        )
    }

    private var broadcastRow: some View {
        settingRow(
            icon: "dot.radiowaves.left.and.right",
            title: L10n(fr: "Envoi multi-destinataires", en: "Multi-recipient send").localized,
            subtitle: L10n(
                fr: "Envoie simultanément à tous les appareils appairés.",
                en: "Sends simultaneously to every paired device."
            ).localized,
            isOn: $draft.broadcastToAll
        )
    }

    private func settingRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
