import SwiftUI

// Bouton nuage réutilisable + arc de 3 cercles (bell/gear/person) qui
// sortent depuis le nuage avec animation staggered. Ouvre les sheets
// Notifications et Settings. Le parent doit garantir que ce composant
// est au TOP du z-order (sinon la card/panneau le masqueront).

struct PoofCloudMenu: View {
    @EnvironmentObject var session: PoofSession
    @StateObject private var profile = PoofProfileImage.shared
    @State private var showCloudMenu = false
    @State private var showNotifications = false
    @State private var showSettings = false
    @State private var showAccount = false

    var body: some View {
        cloudMenuButton
            .overlay(alignment: .topTrailing) {
                cloudMenuCircles
            }
            .onAppear { profile.loadIfNeeded() }
            .sheet(isPresented: $showNotifications) {
                PoofNotificationsView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showSettings) {
                PoofSettingsView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showAccount) {
                PoofAccountView()
            }
    }

    // MARK: - Cloud button

    private var cloudMenuButton: some View {
        Button {
            PoofHaptics.impactMedium()
            showCloudMenu.toggle()
        } label: {
            cloudGlyph
        }
        .buttonStyle(.plain)
    }

    /// Si l'utilisateur a une photo de profil (Me Card iCloud), on remplit le
    /// nuage avec l'image (masquée à la shape SF Symbol). Sinon fallback stroke
    /// nuage vide.
    @ViewBuilder
    private var cloudGlyph: some View {
        if let img = profile.image {
            Image(poofImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 46)
                .mask(
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 46, weight: .regular))
                )
                .overlay(
                    Image(systemName: "cloud")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundColor(.white)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        } else {
            Image(systemName: "cloud")
                .font(.system(size: 46, weight: .regular))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        }
    }

    // MARK: - Menu circles (arc R=80, 180°/225°/270°)

    private var cloudMenuCircles: some View {
        let hiddenX: CGFloat = 3
        let hiddenY: CGFloat = -6
        return ZStack(alignment: .topTrailing) {
            Color.clear
                .frame(width: 34, height: 28)

            menuCircle(icon: "bell.fill") {
                showCloudMenu = false
                showNotifications = true
            }
            .offset(x: showCloudMenu ? -77 : hiddenX, y: hiddenY)
            .opacity(showCloudMenu ? 1 : 0)
            .scaleEffect(showCloudMenu ? 1 : 0.3)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.72)
                    .delay(showCloudMenu ? 0.00 : 0.16),
                value: showCloudMenu
            )

            menuCircle(icon: "gearshape.fill") {
                showCloudMenu = false
                showSettings = true
            }
            .offset(
                x: showCloudMenu ? -54 : hiddenX,
                y: showCloudMenu ? 51 : hiddenY
            )
            .opacity(showCloudMenu ? 1 : 0)
            .scaleEffect(showCloudMenu ? 1 : 0.3)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.72)
                    .delay(0.08),
                value: showCloudMenu
            )

            menuCircle(icon: "person.fill") {
                showCloudMenu = false
                showAccount = true
            }
            .offset(x: hiddenX, y: showCloudMenu ? 74 : hiddenY)
            .opacity(showCloudMenu ? 1 : 0)
            .scaleEffect(showCloudMenu ? 1 : 0.3)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.72)
                    .delay(showCloudMenu ? 0.16 : 0.00),
                value: showCloudMenu
            )
        }
        .allowsHitTesting(showCloudMenu)
    }

    private func menuCircle(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
