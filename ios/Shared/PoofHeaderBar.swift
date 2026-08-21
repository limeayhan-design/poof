import SwiftUI

// Header partagé des 3 tabs (Home / Send / Received) : wordmark "Poof" à
// gauche + PoofCloudMenu à droite. Extrait pour éviter la triple duplication
// et garantir un alignement pixel-perfect entre les tabs.

struct PoofHeaderBar: View {
    /// Long-press optionnel sur le wordmark (utilisé en DEBUG par Send pour
    /// toggle le tier Premium). Nil = pas de gesture.
    var onLongPressPoof: (() -> Void)?

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Text("Poof")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
                    .modifier(OptionalLongPress(action: onLongPressPoof))
                // Badge « beta » discret, honnête. Signale que l'app est en
                // développement actif sans crier ni casser la hiérarchie
                // visuelle du wordmark. Style Superhuman / Linear.
                Text("beta")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                    )
                    .offset(y: -8)
                Spacer()
                PoofCloudMenu()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Color.clear + allowsHitTesting(false) : occupe l'espace pour
            // pousser le HStack en haut, MAIS laisse passer les taps vers les
            // vues en dessous dans le ZStack (SecondCard, card Transfer, etc.).
            Color.clear
                .allowsHitTesting(false)
        }
    }
}

private struct OptionalLongPress: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onLongPressGesture(minimumDuration: 0.6, perform: action)
        } else {
            content
        }
    }
}
