import SwiftUI

/// Prompt de saisie d'un passcode 4-6 chiffres avant l'ouverture d'un
/// fichier Secure. La sheet ne se ferme qu'en cas de succès (`onUnlock`)
/// ou d'annulation explicite par l'utilisateur (`onCancel`).
struct PasscodePromptSheet: View {
    let expectedCode: String
    let onUnlock: () -> Void
    let onCancel: () -> Void

    @State private var input: String = ""
    @State private var errorShake: Bool = false
    @FocusState private var focused: Bool

    private let length: Int = 6

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
        VStack(spacing: 28) {
            VStack(spacing: 14) {
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
                Text(L10n(fr: "Fichier protégé", en: "Protected file").localized)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(L10n(
                    fr: "Saisis le code fourni par l'expéditeur pour ouvrir ce fichier.",
                    en: "Enter the code shared by the sender to open this file."
                ).localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            passcodeField
                .modifier(ShakeEffect(animatableData: errorShake ? 1 : 0))

            Spacer(minLength: 0)
        }
        .padding(.top, 80)
        .padding(.horizontal, 16)
    }

    private var passcodeField: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0 ..< length, id: \.self) { i in
                    passcodeDot(filled: i < input.count)
                }
            }
            #if canImport(UIKit)
            // iOS : TextField invisible derrière les dots, keyboard numpad auto.
            .background(inputField)
            #endif

            #if canImport(AppKit)
                // Mac : pas de touch keyboard, il faut un vrai champ visible pour
                // que la frappe hardware fonctionne. SecureField natif, auto-focus.
                inputField
                    .frame(maxWidth: 220)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
            #endif
        }
        .onAppear { focused = true }
    }

    /// Champ de saisie — SecureField sur les 2 plateformes pour ne pas
    /// exposer les chiffres à l'écran ; invisible côté iOS (les dots font
    /// le visuel), visible côté Mac (le keyboard hardware a besoin d'un
    /// vrai champ focusable).
    private var inputField: some View {
        SecureField("", text: $input)
        #if canImport(UIKit)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .foregroundColor(.clear)
            .tint(.clear)
            .frame(maxWidth: .infinity)
        #else
            .foregroundColor(.white)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
        #endif
            .focused($focused)
            .onSubmit { checkMatch(input) }
            .onChange(of: input) { _, new in
                let filtered = String(new.filter(\.isNumber).prefix(length))
                if filtered != new {
                    input = filtered
                }
                checkMatch(filtered)
            }
    }

    private func passcodeDot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.white : Color.white.opacity(0.20))
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
    }

    private func checkMatch(_ current: String) {
        guard current.count >= 4 else { return }
        if current == expectedCode {
            PoofHaptics.success()
            onUnlock()
        } else if current.count == length {
            PoofHaptics.error()
            withAnimation(.default) { errorShake.toggle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                input = ""
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    PoofHaptics.tap()
                    onCancel()
                } label: {
                    Text(L10n(fr: "Cancel", en: "Cancel").localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .padding(.leading, 16)
                Spacer()
            }
            Spacer()
        }
    }
}

/// Petit shake horizontal pour signaler un mauvais code.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let translation = 10 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
