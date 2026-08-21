import SwiftUI

/// Sheet plein écran ouverte au long-press sur le chip Secure du rectangle
/// Premium. L'utilisateur ajuste les 8 options avant de "Appliquer".
struct SecureConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: SecureConfig
    var onApply: (SecureConfig) -> Void

    @State private var draft: SecureConfig
    @State private var passcodeInput: String = ""
    @State private var watermarkText: String = ""
    @FocusState private var passcodeFocused: Bool
    /// Date sélectionnée par le DatePicker quand `.customDate` est actif.
    /// Défaut : dans 24h — user peut ajuster.
    @State private var customExpiryDate: Date = .init(timeIntervalSinceNow: 60 * 60 * 24)
    /// Dernière valeur d'expiry non-`never` — mémorisée pour restaurer la
    /// sélection quand l'utilisateur toggle OFF puis re-ON l'expiration.
    @State private var lastNonNeverExpiry: ExpiryPolicy?

    init(config: Binding<SecureConfig>, onApply: @escaping (SecureConfig) -> Void) {
        _config = config
        self.onApply = onApply
        _draft = State(initialValue: config.wrappedValue)
        if case let .digits(code) = config.wrappedValue.passcode {
            _passcodeInput = State(initialValue: code)
        }
        if case let .custom(text) = config.wrappedValue.watermark {
            _watermarkText = State(initialValue: text)
        }
        if case let .customDate(date) = config.wrappedValue.expiry {
            _customExpiryDate = State(initialValue: date)
        }
        if config.wrappedValue.expiry != .never {
            _lastNonNeverExpiry = State(initialValue: config.wrappedValue.expiry)
        }
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
                passcodeRow
                expiryRow
                oneTimeRow
                watermarkRow
                biometricsRow
                applyButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 80)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Header

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
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(L10n(fr: "Envoi Secure", en: "Secure send").localized)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(L10n(
                fr: "Configure les protections avant l'envoi. Elles seront appliquées au prochain fichier.",
                en: "Set your protections before sending. They apply to the next file."
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

    private var passcodeRow: some View {
        settingRow(
            icon: "key.fill",
            title: L10n(fr: "Mot de passe", en: "Passcode").localized,
            subtitle: L10n(fr: "4 à 6 chiffres avant l'ouverture", en: "4-6 digits before opening").localized,
            isOn: Binding(
                get: { draft.passcode.isEnabled },
                set: { isOn in
                    if isOn {
                        draft.passcode = .digits(passcodeInput.isEmpty ? "" : passcodeInput)
                    } else {
                        draft.passcode = .off
                    }
                }
            )
        ) {
            if draft.passcode.isEnabled {
                TextField(
                    L10n(fr: "Code (4-6 chiffres)", en: "Code (4-6 digits)").localized,
                    text: $passcodeInput
                )
                #if canImport(UIKit)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .focused($passcodeFocused)
                #if canImport(UIKit)
                    .toolbar {
                        // Bouton OK au-dessus du numberPad (qui n'a pas de Return
                        // natif). Ne s'affiche que quand le champ passcode a le
                        // focus.
                        if passcodeFocused {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button {
                                    passcodeFocused = false
                                } label: {
                                    Text("OK").font(.system(size: 15, weight: .semibold))
                                }
                            }
                        }
                    }
                #endif
                    .onChange(of: passcodeInput) { _, new in
                        let filtered = String(new.filter(\.isNumber).prefix(6))
                        if filtered != new {
                            passcodeInput = filtered
                        }
                        draft.passcode = .digits(filtered)
                    }
                if passcodeInput.count < 4 {
                    Text(L10n(
                        fr: "Le code doit contenir au moins 4 chiffres.",
                        en: "The code must contain at least 4 digits."
                    ).localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.35))
                }
            }
        }
    }

    private var expiryRow: some View {
        settingRow(
            icon: "clock.fill",
            title: L10n(fr: "Expiration", en: "Expiry").localized,
            subtitle: expiryHint,
            // Toggle ON/OFF exactement comme Passcode/Watermark : OFF pose
            // `.never` interne (le fichier reste dans Poof indéfiniment
            // jusqu'à ce que l'utilisateur le ferme lui-même).
            isOn: Binding(
                get: { draft.expiry != .never },
                set: { isOn in
                    if isOn {
                        // Restaure la dernière valeur non-never, ou default 1 jour.
                        draft.expiry = lastNonNeverExpiry ?? .oneDay
                    } else {
                        // Mémorise la sélection courante avant de la remplacer par never.
                        if draft.expiry != .never {
                            lastNonNeverExpiry = draft.expiry
                        }
                        draft.expiry = .never
                    }
                }
            )
        ) {
            if draft.expiry != .never {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(Array(ExpiryPolicy.presets.enumerated()), id: \.offset) { _, policy in
                            expiryChip(policy)
                        }
                        expiryChip(.customDate(customExpiryDate))
                    }
                    if draft.expiry.isCustom {
                        DatePicker(
                            L10n(fr: "Date d'expiration", en: "Expiry date").localized,
                            selection: $customExpiryDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .tint(.white)
                        .onChange(of: customExpiryDate) { _, newDate in
                            draft.expiry = .customDate(newDate)
                        }
                    }
                }
            }
        }
    }

    private var expiryHint: String {
        L10n(
            fr: "Le fichier s'auto-détruit après la période choisie.",
            en: "The file self-destructs after the chosen period."
        ).localized
    }

    private func expiryChip(_ policy: ExpiryPolicy) -> some View {
        // Comparaison structurelle : deux customDate à dates différentes
        // représentent quand même le "même" chip UI (on n'a qu'un seul chip
        // custom, la date change avec le DatePicker).
        let isSelected: Bool = switch (draft.expiry, policy) {
        case (.customDate, .customDate): true
        default: draft.expiry == policy
        }
        return Button {
            draft.expiry = policy
            PoofHaptics.tap()
        } label: {
            Text(policy.label.localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private var oneTimeRow: some View {
        settingRow(
            icon: "eye.slash.fill",
            title: L10n(fr: "Ouverture unique", en: "One-time view").localized,
            subtitle: L10n(
                fr: "Auto-destruction dès la première ouverture.",
                en: "Self-destructs on first open."
            ).localized,
            isOn: $draft.oneTimeView
        ) { EmptyView() }
    }

    private var watermarkRow: some View {
        settingRow(
            icon: "signature",
            title: L10n(fr: "Filigrane", en: "Watermark").localized,
            subtitle: L10n(
                fr: "Nom du destinataire ou texte custom apposé au fichier.",
                en: "Recipient name or custom text on the file."
            ).localized,
            isOn: Binding(
                get: { draft.watermark.isEnabled },
                set: { isOn in
                    draft.watermark = isOn ? .recipientName : .off
                }
            )
        ) {
            if draft.watermark.isEnabled {
                HStack(spacing: 8) {
                    watermarkChoice(L10n(fr: "Destinataire", en: "Recipient").localized, isSelected: {
                        if case .recipientName = draft.watermark {
                            return true
                        }
                        return false
                    }()) {
                        draft.watermark = .recipientName
                    }
                    watermarkChoice(L10n(fr: "Custom", en: "Custom").localized, isSelected: {
                        if case .custom = draft.watermark {
                            return true
                        }
                        return false
                    }()) {
                        draft.watermark = .custom(watermarkText)
                    }
                }
                if case .custom = draft.watermark {
                    TextField(
                        L10n(fr: "Texte du filigrane", en: "Watermark text").localized,
                        text: $watermarkText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .onChange(of: watermarkText) { _, new in
                        draft.watermark = .custom(new)
                    }
                }
            }
        }
    }

    private func watermarkChoice(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private var biometricsRow: some View {
        settingRow(
            icon: "faceid",
            title: L10n(fr: "Face ID / Touch ID requis", en: "Face ID / Touch ID required").localized,
            subtitle: L10n(
                fr: "Le destinataire doit s'authentifier pour ouvrir.",
                en: "Recipient must authenticate to open."
            ).localized,
            isOn: $draft.biometrics
        ) { EmptyView() }
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

    // MARK: - Apply

    /// Vrai si la config est valide et peut être appliquée. Refuse
    /// silencieusement un passcode activé avec moins de 4 chiffres —
    /// sinon la protection serait ignorée à l'usage (`.digits("")`
    /// est traité comme "aucun passcode" par le gate receiver).
    private var isDraftValid: Bool {
        if case let .digits(code) = draft.passcode, code.count < 4 {
            return false
        }
        return true
    }

    private var applyButton: some View {
        Button {
            PoofHaptics.impactMedium()
            onApply(draft)
            dismiss()
        } label: {
            Text(L10n(fr: "Appliquer", en: "Apply").localized)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(isDraftValid ? .black : .black.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isDraftValid ? Color.white : Color.white.opacity(0.55))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isDraftValid)
    }

    // MARK: - Top bar

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
