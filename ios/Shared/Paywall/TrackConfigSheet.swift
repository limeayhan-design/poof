import SwiftUI

/// Sheet plein écran ouverte au long-press sur le chip Track du rectangle
/// Premium. L'utilisateur ajuste les 3 options avant de "Appliquer".
struct TrackConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: TrackConfig
    var onApply: (TrackConfig) -> Void

    @State private var draft: TrackConfig
    @State private var customMessageText: String = ""

    init(config: Binding<TrackConfig>, onApply: @escaping (TrackConfig) -> Void) {
        _config = config
        self.onApply = onApply
        _draft = State(initialValue: config.wrappedValue)
        _customMessageText = State(initialValue: config.wrappedValue.customMessage ?? "")
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
                readReceiptsRow
                notifyRow
                customMessageRow
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
                Image(systemName: "eye.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n(fr: "Envoi Track", en: "Track send").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(L10n(
                fr: "Sais qui a ouvert ton fichier, quand, et attache un message contextuel.",
                en: "Know who opened your file, when, and attach a contextual message."
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

    private var readReceiptsRow: some View {
        settingRow(
            icon: "checkmark.seal.fill",
            title: L10n(fr: "Accusé de lecture", en: "Read receipts").localized,
            subtitle: L10n(
                fr: "Historique + compteur d'ouvertures visible dans Sent.",
                en: "History + open counter visible in Sent."
            ).localized,
            isOn: $draft.readReceipts
        ) { EmptyView() }
    }

    private var notifyRow: some View {
        settingRow(
            icon: "bell.fill",
            title: L10n(fr: "Notification à chaque ouverture", en: "Notify on each open").localized,
            subtitle: L10n(
                fr: "Toast + haptic sur ton appareil quand quelqu'un ouvre.",
                en: "Toast + haptic on your device when someone opens."
            ).localized,
            isOn: $draft.notifyOnOpen
        ) { EmptyView() }
    }

    private var customMessageRow: some View {
        settingRow(
            icon: "text.bubble.fill",
            title: L10n(fr: "Message custom", en: "Custom message").localized,
            subtitle: L10n(
                fr: "Affiché au destinataire au-dessus du fichier (contexte, référence).",
                en: "Shown to the recipient above the file (context, reference)."
            ).localized
        ) {
            TextField(
                L10n(fr: "Ex. Devis N° 12345", en: "e.g. Invoice #12345").localized,
                text: $customMessageText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .onChange(of: customMessageText) { _, new in
                draft.customMessage = new.isEmpty ? nil : new
            }
        }
    }

    // MARK: - Row helper

    private func settingRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>? = nil,
        @ViewBuilder detail: () -> some View
    ) -> some View {
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
                if let isOn {
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                        .tint(.white)
                }
            }
            detail()
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
