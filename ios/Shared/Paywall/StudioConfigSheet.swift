import SwiftUI

/// Sheet plein écran ouverte au long-press sur le chip Studio. Picker
/// des 5 plateformes cibles + toggle watermark avec texte custom.
struct StudioConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: StudioConfig
    var onApply: (StudioConfig) -> Void

    @State private var draft: StudioConfig

    init(config: Binding<StudioConfig>, onApply: @escaping (StudioConfig) -> Void) {
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
                platformPicker
                watermarkRow
                presetsSection
                applyButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 80)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Presets custom

    @StateObject private var presetStore = StudioPresetStore.shared
    @State private var newPresetName: String = ""
    @State private var showSaveField: Bool = false

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n(fr: "Presets sauvegardés", en: "Saved presets").localized)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.leading, 4)
                Spacer()
                Button {
                    PoofHaptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSaveField.toggle()
                    }
                } label: {
                    Image(systemName: showSaveField ? "xmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if showSaveField {
                HStack(spacing: 8) {
                    TextField(
                        L10n(fr: "Nom du preset", en: "Preset name").localized,
                        text: $newPresetName
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    Button(L10n(fr: "Sauver", en: "Save").localized) {
                        guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        PoofHaptics.success()
                        presetStore.save(StudioPreset(name: newPresetName, config: draft))
                        newPresetName = ""
                        withAnimation { showSaveField = false }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                }
            }

            if presetStore.presets.isEmpty {
                Text(L10n(
                    fr: "Aucun preset — sauvegarde la config actuelle pour la rappeler plus tard.",
                    en: "No preset yet — save the current config to recall it later."
                ).localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(presetStore.presets) { preset in
                        presetRow(preset)
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: StudioPreset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: preset.config.platform.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(preset.config.platform.label.localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button {
                PoofHaptics.tap()
                draft = preset.config
            } label: {
                Text(L10n(fr: "Charger", en: "Load").localized)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            Button {
                PoofHaptics.warning()
                presetStore.delete(preset.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
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
                Image(systemName: "film.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n(fr: "Envoi Studio", en: "Studio send").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(L10n(
                fr: "Encode la vidéo aux specs exactes de la plateforme avant l'envoi. Le destinataire poste sans recompression sociale.",
                en: "Encodes the video to the exact platform specs before send. Recipient posts with no social recompression."
            ).localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Platform picker

    private var platformPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n(fr: "Plateforme cible", en: "Target platform").localized)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
                .padding(.leading, 4)
            VStack(spacing: 8) {
                ForEach(StudioPlatform.allCases) { platform in
                    platformRow(platform)
                }
            }
        }
    }

    private func platformRow(_ platform: StudioPlatform) -> some View {
        let isSelected = draft.platform == platform
        return Button {
            draft.platform = platform
            PoofHaptics.tap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: platform.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.label.localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(platform.subtitle.localized)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.35))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Watermark

    private var watermarkRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "signature")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n(fr: "Filigrane", en: "Watermark").localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L10n(
                        fr: "Logo ou handle en overlay coin — actif dans la V2 (encode + composition).",
                        en: "Logo or handle overlay — enabled in V2 (encode + composition)."
                    ).localized)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $draft.applyWatermark)
                    .labelsHidden()
                    .tint(.white)
            }
            if draft.applyWatermark {
                TextField(
                    L10n(fr: "@ton_handle", en: "@your_handle").localized,
                    text: $draft.watermarkText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
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
