import SwiftUI
import UniformTypeIdentifiers

// Received tab — panneau glass qui liste tous les fichiers reçus dans
// les 24 dernières heures. Grid 3-col scrollable, badges Secure/Track
// contextuels, état vide gracieux quand rien n'est arrivé.

struct PoofReceivedView: View {
    @EnvironmentObject var session: PoofSession
    let onOpenHistory: () -> Void
    let onPreviewFile: (URL) -> Void

    // Flash overlay + ripple déclenchés à chaque nouveau fichier reçu.
    @State private var arrivalFlash: Double = 0
    @State private var rippleTrigger: Int = 0
    @State private var panelBounce: CGFloat = 1

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

            // Nuage décoratif en bas — DNA Figma. Wrapped dans un container
            // clippé à la screen width pour éviter que ses 600pt étendent
            // le ZStack parent → sinon PoofHeaderBar prend la largeur du
            // ZStack (600pt) et le wordmark + nuage top-right sortent
            // physiquement du cadre de l'écran.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Image("HeroPhoto")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 600)
                        .opacity(0.75)
                        .offset(y: 40)
                }
                .clipped()
                // Étend le container sous la tab bar (safe area bottom)
                // sinon le nuage est clippé pile au niveau de la barre.
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

            // Panneau glass compact.
            panel
                .frame(width: 370, height: 400)
                .scaleEffect(panelBounce)
                .offset(y: -110)
                .overlay(
                    ArrivalRipple(trigger: rippleTrigger)
                        .allowsHitTesting(false)
                )

            // Header partagé (composant PoofHeaderBar) — dessiné en dernier
            // pour rester au-dessus du panel.
            PoofHeaderBar()

            // Flash blanc court par-dessus tout à l'arrivée d'un fichier.
            Color.white
                .opacity(arrivalFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: session.receivedFiles.count) { oldValue, newValue in
            guard newValue > oldValue else { return }
            triggerArrival()
        }
    }

    /// Séquence dopamine réception : flash blanc court + ripple sur panel +
    /// mini bounce scale du panel. Se joue à chaque nouveau fichier arrivé.
    private func triggerArrival() {
        arrivalFlash = 0.22
        withAnimation(.easeOut(duration: 0.45)) {
            arrivalFlash = 0
        }
        rippleTrigger += 1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            panelBounce = 1.04
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                panelBounce = 1
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Poof")
                .font(.system(size: 34, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
            Spacer()
            Image(systemName: "cloud")
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        }
    }

    // MARK: - Panel glass

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader
            content
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Last 24h")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 2)

            if !recentFiles.isEmpty {
                Text("· \(recentFiles.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }

            Spacer()

            Button(action: onOpenHistory) {
                HStack(spacing: 4) {
                    Text("All history")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content (grid ou empty state)

    @ViewBuilder
    private var content: some View {
        if recentFiles.isEmpty {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(recentFiles) { file in
                        FileTile(file: file) { onPreviewFile(file.url) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(24)
                .background(
                    Circle().fill(Color.white.opacity(0.10))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                )
            Text("Nothing yet")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("Files received in the last 24 hours land here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var recentFiles: [PoofSession.ReceivedFile] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let fm = FileManager.default
        return session.receivedFiles
            .filter { $0.date >= cutoff }
            // Filtre les fichiers physiques 0 bytes ou absents — dernier
            // filet de sécurité si un transfert cassé a échappé aux gates
            // acceptReceivedFile + handle(frame:) receivedBytes check.
            .filter { entry in
                let size = (try? fm.attributesOfItem(atPath: entry.url.path)[.size] as? Int) ?? 0
                return size > 0 && fm.fileExists(atPath: entry.url.path)
            }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Tile

private struct FileTile: View {
    let file: PoofSession.ReceivedFile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.85))

                // Fichier Secure avec passcode : preview masquée (bloc gradient
                // + gros cadenas). Sinon on affiche la preview AsyncImage.
                if isSecureLocked {
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                } else if isImage {
                    AsyncImage(url: file.url) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(Color(white: 0.45))
                        }
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(white: 0.45))
                }

                // Bandeau bas — nom + heure + badges Premium contextuels
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(shortTime)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                        badgesRow
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TileBounceStyle())
    }

    private var isImage: Bool {
        let ext = file.url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp"].contains(ext)
    }

    /// Vrai si le fichier a un passcode OU biometrics Secure → preview doit
    /// être masquée tant que le user n'a pas passé le gate.
    private var isSecureLocked: Bool {
        guard let cfg = file.secureConfig else { return false }
        return cfg.passcode.isEnabled || cfg.biometrics
    }

    // MARK: - Badges

    private var badgesRow: some View {
        HStack(spacing: 3) {
            if file.secureConfig != nil {
                badge(systemName: "lock.shield.fill")
            }
            if file.trackConfig != nil {
                badge(systemName: "eye.fill")
            }
        }
    }

    private func badge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
    }

    private var icon: String {
        let ext = file.url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) {
            return "photo.fill"
        }
        if ["mp4", "mov", "m4v"].contains(ext) {
            return "film.fill"
        }
        if ["pdf"].contains(ext) {
            return "doc.richtext.fill"
        }
        return "doc.fill"
    }

    /// Formatage compact "14:32", "hier 09:12" pour l'affichage tile.
    private var shortTime: String {
        let calendar = Calendar.current
        let df = DateFormatter()
        df.locale = Locale.current
        if calendar.isDateInToday(file.date) {
            df.dateFormat = "HH:mm"
            return df.string(from: file.date)
        }
        df.dateFormat = "HH:mm"
        return "hier " + df.string(from: file.date)
    }
}

// MARK: - Arrival ripple

/// 2 rings blancs qui se propagent depuis le centre du panel — se déclenchent
/// à chaque incrément de `trigger`. Fade + scale 0→2.2 sur 0.7s. Le second
/// ring décale de 0.12s pour un effet "sonar".
private struct ArrivalRipple: View {
    let trigger: Int

    // État initial = expanded (invisible). Le ring n'apparaît que pendant la
    // séquence d'anim déclenchée par un incrément de `trigger`.
    @State private var expandA: Bool = true
    @State private var expandB: Bool = true

    var body: some View {
        ZStack {
            ring(expand: expandA)
            ring(expand: expandB)
        }
        .onChange(of: trigger) { _, _ in
            expandA = false
            expandB = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                withAnimation(.easeOut(duration: 0.7)) { expandA = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                withAnimation(.easeOut(duration: 0.7)) { expandB = true }
            }
        }
    }

    private func ring(expand: Bool) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(expand ? 0 : 0.55), lineWidth: 1.4)
            .frame(width: 60, height: 60)
            .scaleEffect(expand ? 3.2 : 0.6)
    }
}

// MARK: - Press effect

private struct TileBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Received — empty") {
    PoofReceivedView(
        onOpenHistory: {},
        onPreviewFile: { _ in }
    )
    .environmentObject(PoofSession())
}
