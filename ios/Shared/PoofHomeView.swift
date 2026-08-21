import SwiftUI

// Home Poof — présentation de l'app en langage Ripples.
// Fond noir, header minimal (menu / titre / +), cards teintées.
// V1: header + 1 card teal "How Poof works". User valide, puis on ajoute cards 2 & 3.

struct PoofHomeView: View {
    var onGoToSend: () -> Void = {}
    var onOpenPricing: () -> Void = {}

    var body: some View {
        ZStack {
            // 1. Ton fond d'écran avec les nuages
            // (Tu pourras mettre ton image ou ton dégradé ici)
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255), // #005EFF haut
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255) // #797979 bas
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            // 2. Ta carte centrale "Transfer everywhere"
            VStack {
                Text("Transfer everywhere")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(y: 9)

                // Ton icône de nuage et le texte "Poof"
                ZStack {
                    HorizontalDiamond()
                        .stroke(Color.black.opacity(0.5), lineWidth: 20.5)
                        .frame(width: 120, height: 90)
                        .blur(radius: 50)
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 96))
                        .foregroundColor(.white)
                        .offset(y: 55)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
                }
                Text("Discover exclusivity")
                    .offset(y: 170)

                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 230, height: 33)
                    .offset(x: 0, y: -200)
                    .blur(radius: 20)
                    .frame(width: 120, height: 100) // ← taille figée : agrandir le diamond ne bougera plus les voisins
                Text("Poof")
                    .font(.system(size: 50, weight: .semibold))
                    .offset(y: -112)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)

                // Le prix en bas de la carte
                Text("Starts from 4,99€")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .offset(y: -13)
                Rectangle()
                    .fill(Color.white.opacity(100))
                    .frame(width: 145, height: 1)
                    .offset(y: -36)
            }
            .frame(width: 370, height: 394)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0.3), .clear, .clear, .black.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 10 / 255, green: 145 / 255, blue: 255 / 255), // #0A91FF haut
                                Color(red: 10 / 255, green: 120 / 255, blue: 255 / 255) // #0A78FF bas
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            #if os(macOS)
            .offset(y: -150)
            #else
            .offset(y: -80)
            #endif

            // 3. Deuxième rectangle — extrait dans SecondCard pour éviter un
            // compiler timeout SwiftUI (ZStack avec trop de modifiers imbriqués).
            SecondCard()
            #if os(macOS)
                .offset(y: 250)
            #else
                .offset(y: 320)
            #endif

            // Header partagé (composant PoofHeaderBar) — placé en DERNIER
            // dans le ZStack pour que l'arc de cercles apparaisse au-dessus
            // de la card.
            PoofHeaderBar()
        }
    }
}

/// Copie visuelle du rectangle "Transfer everywhere" — même dimensions et
/// même DNA (gradient bleu, corner 30, stroke, shadow). Vide pour l'instant.
private struct SecondCard: View {
    @State private var showChat = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Help & Feedback")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 20)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
        }
        .frame(width: 370, height: 194)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 10 / 255, green: 145 / 255, blue: 255 / 255),
                            Color(red: 10 / 255, green: 120 / 255, blue: 255 / 255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.3), .clear, .clear, .black.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .allowsHitTesting(false)
        )
        // contentShape + onTapGesture appliqués EN DERNIER pour englober tout
        // le rectangle visuel (background inclus).
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {
            PoofHaptics.tap()
            showChat = true
        }
        .sheet(isPresented: $showChat) {
            PoofHelpMenu()
        }
        // ↓ Offset ajustable — modifie x et y ici pour repositionner la card.
        .offset(x: 0, y: -80)
    }
}

/// ← ICI, à ce niveau (pas imbriqué dans PoofHomeView)
struct HorizontalDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

#Preview {
    PoofHomeView()
        .environmentObject(PoofSession())
        .preferredColorScheme(.dark)
}
