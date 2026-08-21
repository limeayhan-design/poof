import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if canImport(ActivityKit)
    import ActivityKit
#endif

// Send tab — page à redesigner.
// Signature conservée pour PoofRootView.

struct PoofSendView: View {
    @EnvironmentObject var session: PoofSession
    @ObservedObject private var premiumStore = PoofPremiumStore.shared
    let onOpenSendSheet: () -> Void
    let onOpenPairing: () -> Void

    @State private var centerIcon: String = "cloud.fill"
    @State private var cloudDragY: CGFloat = 0
    @State private var cloudOpacity: Double = 1
    @State private var cloudScale: CGFloat = 1
    @State private var cloudScaleX: CGFloat = 1
    @State private var cloudScaleY: CGFloat = 1
    @State private var cloudBlur: CGFloat = 0
    @State private var demoTransferId: String = ""
    @State private var didHapticStart: Bool = false
    @State private var didHapticThreshold: Bool = false
    @State private var pageScale: CGFloat = 1
    @State private var pageDim: Double = 0
    @State private var showCloudPanel: Bool = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedPhotoImages: [Image] = []
    @State private var selectedFiles: [URL] = []
    @State private var showFileImporter: Bool = false
    @State private var clipboardPayload: ClipboardPayload?
    @State private var pairedDevices: [PairedDevice?] = [nil, nil, nil]
    @State private var selectedSlotIndex: Int?
    @State private var pickerSlotIndex: Int?
    @State private var unpairTarget: PairedDevice?

    // Modifiers Premium actifs — Secure + Track + Boost. Offline / Studio
    // suivront le même pattern (nil = OFF, instance = ON avec config).
    @State private var secureConfig: SecureConfig?
    @State private var showSecureSheet: Bool = false
    @State private var trackConfig: TrackConfig?
    @State private var showTrackSheet: Bool = false
    @State private var boostConfig: BoostConfig?
    @State private var showBoostSheet: Bool = false
    @State private var offlineConfig: OfflineConfig?
    @State private var showOfflineSheet: Bool = false
    @State private var studioConfig: StudioConfig?
    @State private var showStudioSheet: Bool = false

    // Hint animation row 2 : au 1er affichage, HStack part décalée à gauche (chip 4 peek visible)
    // puis snap back à 0 → user comprend "ça scroll" sans débord permanent.
    @State private var chipsHintOffset: CGFloat = -42
    @State private var chipsHintPlayed: Bool = false

    /// Trigger incrémental pour rejouer le burst de particules à chaque envoi.
    @State private var sendBurstTrigger: Int = 0

    /// Décalage vertical appliqué aux panneaux glass + chips + devices quand le panneau nuage est ouvert.
    private var panelShift: CGFloat {
        showCloudPanel ? 242 : 0
    }

    /// Le panneau ne s'ouvre que si l'utilisateur a choisi un type d'envoi.
    private var canOpenPanel: Bool {
        centerIcon == "photo.fill" || centerIcon == "doc.fill" || centerIcon == "doc.on.clipboard.fill"
    }

    // MARK: - Send pre-requisites

    /// Envoi possible : un type de contenu (ou un fichier) + un destinataire.
    private var isReadyToSend: Bool {
        selectedDevice != nil && (!selectedFiles.isEmpty || centerIcon != "cloud.fill")
    }

    private var needsContent: Bool {
        selectedFiles.isEmpty && centerIcon == "cloud.fill"
    }

    private var needsDestination: Bool {
        selectedDevice == nil
    }

    /// Bloque l'envoi + toast qui dit exactement ce qu'il manque.
    private func triggerMissingHint() {
        PoofHaptics.warning()

        if needsContent, needsDestination {
            session.toast = "Pick a file and a device first"
        } else if needsContent {
            session.toast = "Pick a file first"
        } else if needsDestination {
            session.toast = "Add a device first"
        }
    }

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

            VStack {
                Spacer()

                ZStack {
                    // Cercle net (base)
                    Image("HeroPhoto")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 400, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 5)
                        .padding(.top, -850)

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 10 / 255, green: 226 / 255, blue: 255 / 255),
                                        Color(red: 0 / 255, green: 0 / 255, blue: 255 / 255)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 4)

                        centerIconStack
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: centerIcon)
                    }
                    .frame(width: 109, height: 100)
                    .scaleEffect(x: cloudScale * cloudScaleX, y: cloudScale * cloudScaleY)
                    .blur(radius: cloudBlur)
                    .offset(y: -600 + cloudDragY)
                    .opacity(cloudOpacity * cloudClipFactor)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35, maximumDistance: 8)
                            .onEnded { _ in
                                guard canOpenPanel else { return }
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                                    showCloudPanel.toggle()
                                }
                                PoofHaptics.soft()
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let raw = min(0, value.translation.height)
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) {
                                    cloudDragY = rubberBand(raw)
                                }

                                if !didHapticStart, raw < -4 {
                                    didHapticStart = true
                                    PoofHaptics.soft()
                                }
                                if !didHapticThreshold, raw < -60 {
                                    didHapticThreshold = true
                                    PoofHaptics.impactMedium()
                                }
                            }
                            .onEnded { value in
                                didHapticStart = false
                                didHapticThreshold = false
                                if value.translation.height < -60 {
                                    if isReadyToSend {
                                        launchDemoTransfer()
                                    } else {
                                        withAnimation(.interpolatingSpring(stiffness: 260, damping: 14)) {
                                            cloudDragY = 0
                                        }
                                        triggerMissingHint()
                                    }
                                } else {
                                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 14)) {
                                        cloudDragY = 0
                                    }
                                    PoofHaptics.tap()
                                }
                            }
                    )

                    Image(systemName: PoofPlatform.deviceSFSymbol)
                        .font(Font.system(size: 52).bold())
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 4)
                        .offset(x: -120, y: -600)

                    Text(PoofPlatform.deviceShortLabel)
                        .offset(x: -120, y: -560)

                    destinationSlot
                        .offset(x: 120, y: -600)

                    Text(destinationLabel)
                        .offset(x: 120, y: -560)

                    // Burst de particules blanches qui explosent depuis le
                    // cercle au moment du swipe-launch — pic de dopamine visuel.
                    SendParticleBurst(trigger: sendBurstTrigger)
                        .offset(y: -600 + cloudDragY)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()

            GlassEffectContainer(spacing: 12) {
                ZStack {
                    // Nouveau panneau du haut — apparaît quand le nuage est long-pressed
                    if showCloudPanel {
                        Color.clear
                            .frame(width: 370, height: 230)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    Color.clear
                        .frame(width: 370, height: 230)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .offset(y: panelShift)

                    Color.clear
                        .frame(width: 370, height: 200)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .offset(y: 230 + panelShift)
                }
            }
            .allowsHitTesting(false)

            // Contenu interactif du nouveau panneau — dépend du type sélectionné.
            // Même transition que le rectangle glass → tout se plie/déplie ensemble.
            if showCloudPanel {
                cloudPanelContent
                    .frame(width: 370, height: 230)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            ZStack {
                // Row 1 — Free content types (photo / doc / clipboard)
                glassChip(icon: "photo.fill") { centerIcon = "photo.fill" }
                    .offset(x: -110, y: -55)
                glassChip(icon: "doc.fill") { centerIcon = "doc.fill" }
                    .offset(x: 0, y: -55)
                glassChip(icon: "doc.on.clipboard.fill") {
                    centerIcon = "doc.on.clipboard.fill"
                    // Auto-fetch depuis le pasteboard système au tap chip —
                    // évite de laisser un rectangle vide après un envoi
                    // clipboard précédent (respawn reset `clipboardPayload`).
                    // L'user a copié quelque chose ailleurs entre-temps →
                    // Poof l'affiche direct sans qu'il doive taper le PasteButton.
                    if clipboardPayload == nil {
                        autoLoadClipboardFromSystem()
                    }
                }
                .offset(x: 110, y: -55)

                // Row 2 — Rectangle liquid glass centré sous les 3 chips
                premiumGlassBar
                    .offset(y: 55)
            }
            .offset(y: panelShift)

            deviceBubble(index: 0).offset(x: -109, y: 200 + panelShift)
            Text(bubbleLabel(0))
                .offset(x: -109, y: 270 + panelShift)
            deviceBubble(index: 1).offset(x: 0, y: 200 + panelShift)
            Text(bubbleLabel(1))
                .offset(x: 0, y: 270 + panelShift)
            deviceBubble(index: 2).offset(x: 109, y: 200 + panelShift)
            Text(bubbleLabel(2))
                .offset(x: 109, y: 270 + panelShift)

            // Header partagé — dessiné par-dessus tout le reste (HeroPhoto,
            // panneaux glass, chips…). Long-press DEBUG toggle Premium.
            PoofHeaderBar(onLongPressPoof: {
                #if DEBUG
                    PoofPremiumStore.shared.debugTogglePremium()
                    let now = PoofPremiumStore.shared.isPremium
                    session.toast = now ? "DEBUG: Premium unlocked" : "DEBUG: Premium locked"
                    PoofHaptics.success()
                #endif
            })
            .zIndex(999)
        }
        .scaleEffect(pageScale, anchor: .top)
        .overlay(Color.black.opacity(pageDim).ignoresSafeArea().allowsHitTesting(false))
        .sheet(isPresented: Binding(
            get: { pickerSlotIndex != nil },
            set: {
                if !$0 {
                    pickerSlotIndex = nil
                }
            }
        )) {
            PoofAddDeviceSheet { device in
                addPairedDevice(device)
            }
            .environmentObject(session)
        }
        .onAppear { syncPairedDevicesFromSession() }
        .onChange(of: session.peers.peers) { _, _ in
            syncPairedDevicesFromSession()
        }
        .onChange(of: centerIcon) { _, _ in
            // Un modifier peut devenir incompatible avec le nouveau type de
            // contenu (ex : Studio actif → l'user choisit Photo). On le
            // désactive silencieusement pour éviter le mode fantôme.
            for kind in PremiumFeatureKind.allCases where !isModifierCompatible(kind) && isModifierActive(kind) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    disableIncompatibleModifier(kind)
                }
                session.toast = "\(kind.rawValue.capitalized) disabled — \(incompatibilityReason(kind))"
                PoofHaptics.warning()
            }
        }
        .confirmationDialog(
            unpairTarget?.name.map { "Unpair \($0)?" } ?? "Unpair device?",
            isPresented: Binding(
                get: { unpairTarget != nil },
                set: {
                    if !$0 {
                        unpairTarget = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: unpairTarget
        ) { device in
            Button("Unpair", role: .destructive) { performUnpair(device) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This device will be removed from Poof on both sides.")
        }
        .sheet(isPresented: $showSecureSheet) {
            SecureConfigSheet(
                config: Binding(
                    get: { secureConfig ?? .defaults },
                    set: { secureConfig = $0 }
                )
            ) { applied in
                secureConfig = applied
            }
        }
        .sheet(isPresented: $showTrackSheet) {
            TrackConfigSheet(
                config: Binding(
                    get: { trackConfig ?? .defaults },
                    set: { trackConfig = $0 }
                )
            ) { applied in
                trackConfig = applied
            }
        }
        .sheet(isPresented: $showBoostSheet) {
            BoostConfigSheet(
                config: Binding(
                    get: { boostConfig ?? .defaults },
                    set: { boostConfig = $0 }
                )
            ) { applied in
                boostConfig = applied
            }
        }
        .sheet(isPresented: $showOfflineSheet) {
            OfflineConfigSheet(
                config: Binding(
                    get: { offlineConfig ?? .defaults },
                    set: { offlineConfig = $0 }
                ),
                offline: session.offline,
                linkedDevices: pairedDevices.compactMap { device in
                    guard let device, let peerId = device.peerId, !peerId.isEmpty else { return nil }
                    return device
                }
            ) { applied in
                offlineConfig = applied
                applyOfflineActivation(applied)
            }
        }
        .sheet(isPresented: $showStudioSheet) {
            StudioConfigSheet(
                config: Binding(
                    get: { studioConfig ?? .defaults },
                    set: { studioConfig = $0 }
                )
            ) { applied in
                studioConfig = applied
            }
        }
    }

    /// Active / désactive advertising + browsing du manager MC selon le
    /// contrat Offline courant. Isole les side-effects réseau au moment
    /// où l'utilisateur applique explicitement le mode.
    private func applyOfflineActivation(_ config: OfflineConfig) {
        // Identité stable pour l'annonce MC + filtrage auto-invite. On les
        // pousse AVANT (re)start advertising sinon le discoveryInfo émis
        // reste figé aux anciennes valeurs.
        session.offline.selfPeerPoofId = PoofDeviceIdentity.deviceId
        session.offline.targetPeerPoofIds = config.linkedDeviceIds
        if config.advertise {
            if session.offline.isAdvertising {
                session.offline.restartAdvertisingIfNeeded()
            } else {
                session.offline.startAdvertising()
            }
        } else {
            session.offline.stopAdvertising()
        }
        session.offline.startBrowsing()
    }

    // MARK: - Premium banner

    /// Rectangle centré sous les 3 chips row 1 (320×100).
    /// Pendant la beta pré-launch Premium : on affiche TOUJOURS la barre de
    /// progression « 20 envois = 1 mois Premium offert au lancement », y
    /// compris quand `debugPremium` est ON — sinon Uras ne voyait pas la
    /// modif sur Mac où le flag debug était resté activé.
    /// Le tap ouvre `PremiumComingSoonView` (via `PoofPremiumGate`).
    private var premiumGlassBar: some View {
        premiumLockedBar
    }

    private var premiumLockedBar: some View {
        Button {
            PoofPremiumGate.shared.present()
        } label: {
            BetaProgressBar()
        }
        .buttonStyle(PressBounceStyle())
    }

    private var premiumUnlockedBar: some View {
        let kinds = PremiumFeatureKind.allCases
        let runs = computeActiveRuns(kinds: kinds)
        return ZStack {
            activeRunsFill(runs: runs, total: kinds.count)
            HStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { idx, kind in
                    premiumIconButton(kind, position: chipPosition(idx: idx, count: kinds.count))
                }
            }
            activeRunsStroke(runs: runs, total: kinds.count)
        }
        .frame(width: 320, height: 100)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Runs de chips actifs (fusion visuelle des strokes)

    private struct ActiveRun: Identifiable {
        let start: Int
        let count: Int
        var id: Int {
            start
        }

        var end: Int {
            start + count - 1
        }
    }

    /// Regroupe les chips actifs consécutifs en "runs" — un run = un bloc
    /// contigu qui recevra un unique fill + stroke fusionné, sans coutures
    /// visibles entre chips.
    private func computeActiveRuns(kinds: [PremiumFeatureKind]) -> [ActiveRun] {
        var runs: [ActiveRun] = []
        var currentStart: Int?
        for (idx, kind) in kinds.enumerated() {
            if isModifierActive(kind) {
                if currentStart == nil {
                    currentStart = idx
                }
            } else if let start = currentStart {
                runs.append(ActiveRun(start: start, count: idx - start))
                currentStart = nil
            }
        }
        if let start = currentStart {
            runs.append(ActiveRun(start: start, count: kinds.count - start))
        }
        return runs
    }

    /// Shape d'un run — radius extérieur (24) sur les bords qui touchent
    /// le rectangle glass parent, radius interne (14) sur les côtés
    /// jouxtant un chip non-actif.
    private func runShape(_ run: ActiveRun, total: Int) -> UnevenRoundedRectangle {
        let outer: CGFloat = 24
        let inner: CGFloat = 14
        let leftRadius: CGFloat = run.start == 0 ? outer : inner
        let rightRadius: CGFloat = run.end == total - 1 ? outer : inner
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: leftRadius,
                bottomLeading: leftRadius,
                bottomTrailing: rightRadius,
                topTrailing: rightRadius
            ),
            style: .continuous
        )
    }

    /// Fond translucide sous les icônes pour chaque run actif.
    private func activeRunsFill(runs: [ActiveRun], total: Int) -> some View {
        let slotWidth: CGFloat = 320.0 / CGFloat(total)
        return ZStack(alignment: .leading) {
            Color.clear
            ForEach(runs) { run in
                runShape(run, total: total)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: slotWidth * CGFloat(run.count), height: 100)
                    .offset(x: slotWidth * CGFloat(run.start))
            }
        }
        .allowsHitTesting(false)
    }

    /// Bord blanc unique par run — pas de couture entre deux chips actifs.
    private func activeRunsStroke(runs: [ActiveRun], total: Int) -> some View {
        let slotWidth: CGFloat = 320.0 / CGFloat(total)
        return ZStack(alignment: .leading) {
            Color.clear
            ForEach(runs) { run in
                runShape(run, total: total)
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: slotWidth * CGFloat(run.count), height: 100)
                    .offset(x: slotWidth * CGFloat(run.start))
            }
        }
        .allowsHitTesting(false)
    }

    /// Position d'un chip dans la row — utilisée pour aligner le radius du
    /// bord actif avec celui du rectangle parent (sinon décalage visible sur
    /// les extrémités gauche et droite).
    private enum ChipPosition { case first, middle, last }

    private func chipPosition(idx: Int, count: Int) -> ChipPosition {
        if idx == 0 {
            return .first
        }
        if idx == count - 1 {
            return .last
        }
        return .middle
    }

    private func premiumIconButton(_ kind: PremiumFeatureKind, position _: ChipPosition) -> some View {
        let compatible = isModifierCompatible(kind)
        // Le stroke/fill des chips actifs est dessiné par `activeRunsOverlay`
        // au niveau du HStack parent, ce qui permet la fusion visuelle quand
        // deux chips adjacents sont sélectionnés en même temps. Un chip
        // incompatible avec le type courant est grisé et non-toggle-able —
        // tap = toast explicatif, long-press = idem.
        return Button {
            if compatible {
                PoofHaptics.soft()
                toggleModifier(kind)
            } else {
                PoofHaptics.warning()
                session.toast = incompatibilityReason(kind)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Text(kind.rawValue.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(compatible ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressBounceStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if compatible {
                    PoofHaptics.impactMedium()
                    openModifierSettings(kind)
                } else {
                    PoofHaptics.warning()
                    session.toast = incompatibilityReason(kind)
                }
            }
        )
    }

    // MARK: - Compatibility entre modifier et type de contenu

    /// Studio encode des vidéos → grisé quand le type sélectionné est
    /// une photo ou du clipboard texte. Les autres modifiers restent
    /// universellement dispo (ils n'ont pas de contrainte de format).
    private func isModifierCompatible(_ kind: PremiumFeatureKind) -> Bool {
        switch kind {
        case .studio:
            centerIcon != "photo.fill"
                && centerIcon != "doc.on.clipboard.fill"
        default:
            true
        }
    }

    /// Message affiché en toast quand l'utilisateur tap un chip grisé —
    /// explique pourquoi la feature n'est pas dispo sur ce type de contenu.
    private func incompatibilityReason(_ kind: PremiumFeatureKind) -> String {
        switch kind {
        case .studio:
            L10n(
                fr: "Studio nécessite une vidéo.",
                en: "Studio needs a video."
            ).localized
        default:
            ""
        }
    }

    /// Shape du chip qui matche pile le radius parent sur les côtés extérieurs
    /// (24) et garde un radius interne plus serré (14) sur les côtés qui
    /// jouxtent un autre chip — évite le petit décalage disgracieux entre le
    /// bord blanc actif et le bord du rectangle glass parent.
    private func chipShape(position: ChipPosition) -> UnevenRoundedRectangle {
        let outer: CGFloat = 24
        let inner: CGFloat = 14
        let radii = switch position {
        case .first:
            RectangleCornerRadii(topLeading: outer, bottomLeading: outer, bottomTrailing: inner, topTrailing: inner)
        case .middle:
            RectangleCornerRadii(topLeading: inner, bottomLeading: inner, bottomTrailing: inner, topTrailing: inner)
        case .last:
            RectangleCornerRadii(topLeading: inner, bottomLeading: inner, bottomTrailing: outer, topTrailing: outer)
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }

    // MARK: - Center icon (type + modifiers empilés)

    /// Symbole SF du type de contenu courant, ou nil si l'utilisateur n'a
    /// encore choisi ni photo / doc / clipboard.
    private var contentTypeIcon: String? {
        switch centerIcon {
        case "photo.fill", "doc.fill", "doc.on.clipboard.fill":
            centerIcon
        default:
            nil
        }
    }

    /// Icônes des modifiers Premium actuellement actifs (pour l'instant Secure
    /// seul, la liste s'étoffera avec Track/Boost/Offline/Studio).
    private var activeModifierIcons: [String] {
        var icons: [String] = []
        if secureConfig != nil {
            icons.append(PremiumFeatureKind.secure.icon)
        }
        if trackConfig != nil {
            icons.append(PremiumFeatureKind.track.icon)
        }
        if boostConfig != nil {
            icons.append(PremiumFeatureKind.boost.icon)
        }
        if offlineConfig != nil {
            icons.append(PremiumFeatureKind.offline.icon)
        }
        if studioConfig != nil {
            icons.append(PremiumFeatureKind.studio.icon)
        }
        return icons
    }

    /// Rendu du contenu du cercle central. Compose type de contenu + modifiers
    /// Premium actifs avec un léger offset diagonal, comme le logo Poof
    /// (cloud + arrow). Fallback : cloud.fill quand rien n'est actif.
    @ViewBuilder
    private var centerIconStack: some View {
        let type = contentTypeIcon
        let modifiers = activeModifierIcons

        return ZStack {
            if type == nil, modifiers.isEmpty {
                centerSymbol("cloud.fill", size: 42)
                    .transition(.scale.combined(with: .opacity))
            } else if let type, modifiers.isEmpty {
                centerSymbol(type, size: 42)
                    .id("solo-\(type)")
                    .transition(.scale.combined(with: .opacity))
            } else if type == nil, modifiers.count == 1 {
                centerSymbol(modifiers[0], size: 40)
                    .id("solo-\(modifiers[0])")
                    .transition(.scale.combined(with: .opacity))
            } else if let type, modifiers.count == 1 {
                // 1 modifier + 1 type : superposition diagonale, style logo Poof
                // (cloud + arrow). Reste lisible avec 2 icônes seulement.
                ZStack {
                    centerSymbol(type, size: 34)
                        .offset(x: -8, y: 8)
                    centerSymbol(modifiers[0], size: 28)
                        .offset(x: 14, y: -10)
                        .transition(.scale.combined(with: .opacity))
                }
                .transition(.opacity)
            } else {
                // 2+ modifiers : type (ou cloud fallback) au centre + modifiers
                // en anneau autour — même métaphore que le hero orbite du paywall.
                centerRingLayout(centerName: type ?? "cloud.fill", modifiers: modifiers)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: type)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: modifiers)
    }

    /// Compose le contenu du cercle central avec une icône centrale (type de
    /// fichier) et les modifiers Premium disposés en anneau à angles égaux.
    /// Rayon 36pt : tient dans le cercle 109×100 avec ~14pt d'icône (bord à ~50).
    /// Chaque icône orbite est identifiée par son nom (stable) pour que SwiftUI
    /// puisse animer les déplacements quand l'anneau se redistribue.
    private func centerRingLayout(centerName: String, modifiers: [String]) -> some View {
        ZStack {
            centerSymbol(centerName, size: 30)
                .id("center-\(centerName)")
                .transition(.scale.combined(with: .opacity))

            ForEach(Array(modifiers.enumerated()), id: \.element) { idx, name in
                let angle = 2 * .pi * Double(idx) / Double(modifiers.count) - .pi / 2
                let radius: CGFloat = 36
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                miniOrbitSymbol(name)
                    .offset(x: x, y: y)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity),
                        removal: .scale(scale: 0.1).combined(with: .opacity)
                    ))
            }
        }
    }

    /// Version compacte d'une icône SF Symbol pour l'orbite — plus petite,
    /// ombre plus marquée pour rester lisible sur fond bleu du cercle.
    private func miniOrbitSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }

    private func centerSymbol(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(Font.system(size: size).bold())
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 4)
    }

    // MARK: - Modifier toggle / settings

    private func isModifierActive(_ kind: PremiumFeatureKind) -> Bool {
        switch kind {
        case .secure: secureConfig != nil
        case .track: trackConfig != nil
        case .boost: boostConfig != nil
        case .offline: offlineConfig != nil
        case .studio: studioConfig != nil
        }
    }

    private func toggleModifier(_ kind: PremiumFeatureKind) {
        // Toutes les mutations passent par une spring pour que la fusion
        // des runs de chips ET l'apparition/disparition des icônes en
        // anneau soient animées de la même façon (feel unifié).
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            switch kind {
            case .secure:
                secureConfig = secureConfig == nil ? .defaults : nil
            case .track:
                trackConfig = trackConfig == nil ? .defaults : nil
            case .boost:
                boostConfig = boostConfig == nil ? .defaults : nil
            case .offline:
                if offlineConfig == nil {
                    // Pré-remplit avec TOUS les paired devices connus — au 1er
                    // tap l'utilisateur veut typiquement joindre ses appareils
                    // déjà appairés sans passer par le sheet. Il pourra
                    // décocher via long-press.
                    var base = OfflineConfig.defaults
                    base.linkedDeviceIds = Set(pairedDevices.compactMap { $0?.peerId })
                    offlineConfig = base
                    applyOfflineActivation(base)
                } else {
                    offlineConfig = nil
                    session.offline.stopAll()
                }
            case .studio:
                studioConfig = studioConfig == nil ? .defaults : nil
            }
        }
    }

    /// Force la mise à nil d'un modifier — utilisé quand un changement de
    /// type de contenu le rend incompatible (ex : Studio + Photo).
    /// Ne trigger pas `withAnimation` en interne, le caller le fait.
    private func disableIncompatibleModifier(_ kind: PremiumFeatureKind) {
        switch kind {
        case .secure: secureConfig = nil
        case .track: trackConfig = nil
        case .boost: boostConfig = nil
        case .offline:
            offlineConfig = nil
            session.offline.stopAll()
        case .studio: studioConfig = nil
        }
    }

    private func openModifierSettings(_ kind: PremiumFeatureKind) {
        switch kind {
        case .secure:
            // S'assure qu'un config existe avant d'ouvrir (l'user ouvre les
            // réglages même si le mode n'est pas encore "activé" → on init
            // les defaults à ce moment).
            if secureConfig == nil {
                secureConfig = .defaults
            }
            showSecureSheet = true
        case .track:
            if trackConfig == nil {
                trackConfig = .defaults
            }
            showTrackSheet = true
        case .boost:
            if boostConfig == nil {
                boostConfig = .defaults
            }
            showBoostSheet = true
        case .offline:
            if offlineConfig == nil {
                var base = OfflineConfig.defaults
                base.linkedDeviceIds = Set(pairedDevices.compactMap { $0?.peerId })
                offlineConfig = base
                applyOfflineActivation(base)
            }
            // Lance browsing automatiquement à l'ouverture du sheet pour
            // que l'utilisateur voie apparaître les devices à proximité.
            session.offline.startBrowsing()
            showOfflineSheet = true
        case .studio:
            if studioConfig == nil {
                studioConfig = .defaults
            }
            showStudioSheet = true
        }
    }

    // MARK: - Devices

    private var selectedDevice: PairedDevice? {
        guard let idx = selectedSlotIndex, pairedDevices.indices.contains(idx) else { return nil }
        return pairedDevices[idx]
    }

    @ViewBuilder
    private var destinationSlot: some View {
        if let device = selectedDevice {
            Image(systemName: device.kind.sfSymbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                )
                .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        }
    }

    private var destinationLabel: String {
        selectedDevice?.kind.displayName ?? "Add device"
    }

    private func deviceBubble(index: Int) -> some View {
        DeviceBubble(
            device: pairedDevices[index],
            isSelected: selectedSlotIndex == index,
            onTap: { handleBubbleTap(index) },
            onLongPress: { handleBubbleLongPress(index) }
        )
    }

    private func bubbleLabel(_ index: Int) -> String {
        pairedDevices[index]?.kind.displayName ?? "Empty"
    }

    private func handleBubbleTap(_ index: Int) {
        if pairedDevices[index] == nil {
            pickerSlotIndex = index
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                selectedSlotIndex = index
            }
            PoofHaptics.soft()
        }
    }

    private func addPairedDevice(_ device: PairedDevice) {
        guard let idx = pickerSlotIndex else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            pairedDevices[idx] = device
            selectedSlotIndex = idx
        }
        pickerSlotIndex = nil
        PoofHaptics.success()
    }

    private func handleBubbleLongPress(_ index: Int) {
        guard let device = pairedDevices[index] else { return }
        PoofHaptics.impactMedium()
        unpairTarget = device
    }

    /// Reconstruit les 3 slots depuis `session.peers.peers`.
    /// Préserve l'ordre existant : un peer déjà dans un slot y reste,
    /// les nouveaux peers vont dans les slots vides (gauche → droite).
    private func syncPairedDevicesFromSession() {
        let sessionPeers = session.peers.peers
        var next: [PairedDevice?] = pairedDevices

        // Purge les slots dont le peer n'existe plus côté session.
        for i in next.indices {
            if let slot = next[i], let pid = slot.peerId,
               !sessionPeers.contains(where: { $0.id == pid })
            {
                next[i] = nil
                if selectedSlotIndex == i {
                    selectedSlotIndex = nil
                }
            }
        }

        // Rafraîchit noms et insère les nouveaux peers dans le premier slot libre.
        for peer in sessionPeers {
            if let existingIdx = next.firstIndex(where: { $0?.peerId == peer.id }) {
                next[existingIdx] = PairedDevice(
                    kind: PoofAddDeviceSheet.deviceKind(for: peer.platform),
                    name: peer.name,
                    peerId: peer.id
                )
                continue
            }
            if let freeIdx = next.firstIndex(where: { $0 == nil }) {
                next[freeIdx] = PairedDevice(
                    kind: PoofAddDeviceSheet.deviceKind(for: peer.platform),
                    name: peer.name,
                    peerId: peer.id
                )
            }
        }

        if next != pairedDevices {
            pairedDevices = next
        }
    }

    private func performUnpair(_ device: PairedDevice) {
        // Retire le slot local même si peerId est nil (slot legacy sans peer réel).
        let idx: Int? = {
            if let pid = device.peerId {
                return pairedDevices.firstIndex(where: { $0?.peerId == pid })
            }
            return pairedDevices.firstIndex(where: { $0 == device })
        }()
        if let idx {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                pairedDevices[idx] = nil
                if selectedSlotIndex == idx {
                    selectedSlotIndex = nil
                }
            }
        }
        if let pid = device.peerId {
            session.unpair(pid)
        }
        PoofHaptics.success()
    }

    private func glassChip(icon: String? = nil, action: @escaping () -> Void = {}) -> some View {
        GlassChip(icon: icon, action: action)
    }

    // MARK: - Panneau nuage (contenu dépend du type sélectionné)

    private var cloudPanelContent: some View {
        Group {
            switch centerIcon {
            case "photo.fill": photoPanel
            case "doc.fill": docPanel
            case "doc.on.clipboard.fill": clipboardPanel
            default: EmptyView()
            }
        }
        .id(centerIcon)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 1.04))
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: centerIcon)
    }

    private var photoPanel: some View {
        Group {
            if selectedPhotoImages.isEmpty {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 0, matching: .images) {
                    panelEmptyState(icon: "photo.badge.plus.fill", label: "Choose a photo")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(selectedPhotoImages.enumerated()), id: \.offset) { idx, img in
                            photoTile(img: img, index: idx)
                        }
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 0, matching: .images) {
                            addMoreTile
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minWidth: 370, alignment: .center)
                }
                .frame(width: 370, height: 230)
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await loadSelectedPhotos(newItems) }
        }
    }

    private func photoTile(img: Image, index: Int) -> some View {
        img
            .resizable()
            .scaledToFill()
            .frame(width: 110, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    removePhoto(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(4)
                }
            }
    }

    private func removePhoto(at index: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if selectedPhotoImages.indices.contains(index) {
                selectedPhotoImages.remove(at: index)
            }
            if selectedPhotos.indices.contains(index) {
                selectedPhotos.remove(at: index)
            }
        }
        PoofHaptics.soft()
    }

    private var docPanel: some View {
        Group {
            if selectedFiles.isEmpty {
                Button {
                    poofLog("[Poof] Choose a file tapped")
                    triggerFilePicker()
                } label: {
                    panelEmptyState(icon: "doc.badge.plus", label: "Choose a file")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(selectedFiles, id: \.self) { url in
                                fileRow(url)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Button {
                        triggerFilePicker()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add more")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 370, height: 230)
            }
        }
        #if !os(macOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                selectedFiles.append(contentsOf: urls.filter { !selectedFiles.contains($0) })
            }
        }
        #endif
    }

    /// Ouvre le picker de fichier — `.fileImporter` sur iOS (marche parfaitement),
    /// `NSOpenPanel.runModal()` sur macOS (le `.fileImporter` échoue à s'afficher
    /// quand il est attaché à un panel dans un ZStack overlay).
    private func triggerFilePicker() {
        #if os(macOS)
            // Dispatch async pour laisser SwiftUI finir le cycle d'event
            // AVANT de lancer un runModal bloquant (sinon la modal ne
            // s'affiche pas). L'activate garantit que la fenêtre Poof est
            // focus quand la sheet système apparaît.
            DispatchQueue.main.async {
                PoofPlatform.pickFiles(allowMultiple: true) { urls in
                    poofLog("[Poof] File picker returned \(urls.count) file(s)")
                    let unique = urls.filter { !selectedFiles.contains($0) }
                    if !unique.isEmpty {
                        selectedFiles.append(contentsOf: unique)
                    }
                }
            }
        #else
            showFileImporter = true
        #endif
    }

    private func panelEmptyState(icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 370, height: 230)
        .contentShape(Rectangle())
    }

    private var addMoreTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .frame(width: 110, height: 150)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSizeString(url))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            Button {
                selectedFiles.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var images: [Image] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = PoofImage(data: data)
            {
                images.append(Image(poofImage: ui))
            }
        }
        await MainActor.run { selectedPhotoImages = images }
    }

    private func fileSizeString(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let bytes = Int64(values?.fileSize ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Clipboard

    @ViewBuilder
    private var clipboardPanel: some View {
        if let payload = clipboardPayload {
            clipboardPreview(payload)
        } else {
            clipboardEmpty
        }
    }

    private var clipboardEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Text("Nothing to send yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            PasteButton(supportedContentTypes: [.image, .url, .plainText]) { providers in
                loadClipboardProviders(providers)
            }
            .buttonBorderShape(.capsule)
            .tint(.white)
            .labelStyle(.titleAndIcon)
        }
        .frame(width: 370, height: 230)
    }

    private func clipboardPreview(_ payload: ClipboardPayload) -> some View {
        ZStack {
            if case let .text(str) = payload {
                clipboardTextPreview(str)
            } else if case let .url(url) = payload {
                clipboardURLPreview(url)
            } else if case let .image(img) = payload {
                clipboardImagePreview(img)
            }
        }
        .frame(width: 370, height: 230)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    clipboardPayload = nil
                }
                PoofHaptics.soft()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(10)
            }
        }
    }

    private func clipboardTextPreview(_ str: String) -> some View {
        ScrollView {
            Text(str)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 330, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }

    private func clipboardURLPreview(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text(url.absoluteString)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }

    private func clipboardImagePreview(_ img: PoofImage) -> some View {
        Image(poofImage: img)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 220, maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Lit le pasteboard système et remplit `clipboardPayload` si un contenu
    /// utilisable existe. Utilisé au tap chip clipboard pour éviter d'afficher
    /// un rectangle vide alors que l'user vient de copier quelque chose.
    private func autoLoadClipboardFromSystem() {
        #if canImport(UIKit)
            let pb = UIPasteboard.general
            if let img = pb.image {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    clipboardPayload = .image(img)
                }
                return
            }
            if let url = pb.url {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    clipboardPayload = .url(url)
                }
                return
            }
            if let str = pb.string, !str.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    clipboardPayload = .text(str)
                }
                return
            }
        #elseif canImport(AppKit)
            let pb = NSPasteboard.general
            if let str = pb.string(forType: .string), !str.isEmpty {
                if let url = URL(string: str), url.scheme != nil {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        clipboardPayload = .url(url)
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        clipboardPayload = .text(str)
                    }
                }
            }
        #endif
    }

    private func loadClipboardProviders(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        // Ordre de priorité : image → URL → texte (l'image est la plus riche).
        if provider.canLoadObject(ofClass: PoofImage.self) {
            provider.loadObject(ofClass: PoofImage.self) { obj, _ in
                guard let img = obj as? PoofImage else { return }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        clipboardPayload = .image(img)
                    }
                    PoofHaptics.soft()
                }
            }
        } else if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                guard let url = obj as? URL else { return }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        clipboardPayload = .url(url)
                    }
                    PoofHaptics.soft()
                }
            }
        } else if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let str = obj as? String else { return }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        clipboardPayload = .text(str)
                    }
                    PoofHaptics.soft()
                }
            }
        }
    }

    /// Hard clip du cercle quand il passe sous la zone Dynamic Island (visuellement "coupé").
    /// Lié directement à cloudDragY → recalculé à chaque frame en même temps que la position,
    /// impossible de désynchroniser fade et vol.
    private var cloudClipFactor: Double {
        if cloudDragY > -100 {
            return 1
        }
        if cloudDragY < -180 {
            return 0
        }
        return Double((cloudDragY + 180) / 80)
    }

    /// Rubber-band resistance — plus tu tires, plus ça résiste (formule Apple UIScrollView).
    private func rubberBand(_ offset: CGFloat) -> CGFloat {
        let d = abs(offset)
        let c: CGFloat = 0.55
        let dim: CGFloat = 180 // dimension de référence pour l'élasticité
        let resistance = (1.0 - (1.0 / ((d * c / dim) + 1.0))) * dim
        return offset < 0 ? -resistance : resistance
    }

    private func resolveTargetPeerId() -> String? {
        if let active = session.activePeerId {
            return active
        }
        if let last = session.peers.peers.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first {
            session.openSession(with: last.id)
            return last.id
        }
        return nil
    }

    private func performRealSend() {
        guard resolveTargetPeerId() != nil else {
            session.toast = "No paired device"
            return
        }

        switch centerIcon {
        case "doc.fill":
            for url in selectedFiles {
                sendSecurityScoped(url)
            }
            selectedFiles.removeAll()

        case "doc.on.clipboard.fill":
            guard let payload = clipboardPayload else {
                session.toast = "Nothing to send"
                return
            }
            // Texte / URL → passent par le relay HTTPS clipboard : arrive
            // sur le receiver MÊME si son app n'est pas ouverte. Notif APNS
            // avec bouton « 📋 Coller » qui écrit le pasteboard sans lancer
            // l'app. Les images clipboard restent sur le pipeline fichier
            // classique (car pas d'API pasteboard cross-device pour bitmap).
            switch payload {
            case let .text(str):
                session.sendClipboardViaRelay(text: str)
            case let .url(url):
                session.sendClipboardViaRelay(text: url.absoluteString)
            case let .image(img):
                sendImage(img)
            }
            clipboardPayload = nil

        case "photo.fill":
            let items = selectedPhotos
            guard !items.isEmpty else {
                session.toast = "Nothing to send"
                return
            }
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    await MainActor.run { writeAndSend(data: data, ext: "jpg", mime: "image/jpeg") }
                }
                await MainActor.run {
                    selectedPhotos.removeAll()
                    selectedPhotoImages.removeAll()
                }
            }

        default:
            session.toast = "Pick something to send first"
        }
    }

    private func sendSecurityScoped(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofOutgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            session.sendFile(
                at: dest,
                secureConfig: secureConfig,
                trackConfig: trackConfig,
                boostConfig: boostConfig,
                studioConfig: studioConfig,
                offlineConfig: offlineConfig
            )
        } catch {
            session.toast = "Send failed: \(error.localizedDescription)"
        }
    }

    private func sendImage(_ img: PoofImage) {
        guard let data = img.poofPNGData else { return }
        writeAndSend(data: data, ext: "png", mime: "image/png")
    }

    private func writeAndSend(data: Data, ext: String, mime: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofOutgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let name = "poof-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).\(ext)"
        let dest = tempDir.appendingPathComponent(name)
        do {
            try data.write(to: dest)
            session.sendFile(
                at: dest,
                mime: mime,
                secureConfig: secureConfig,
                trackConfig: trackConfig,
                boostConfig: boostConfig,
                studioConfig: studioConfig,
                offlineConfig: offlineConfig
            )
        } catch {
            session.toast = "Send failed: \(error.localizedDescription)"
        }
    }

    private func launchDemoTransfer() {
        performRealSend()
        // Pic de dopamine : haptique sendStart + burst particules pile au moment
        // où le cercle décolle. impactMedium ci-dessous vient renforcer le drop.
        PoofHaptics.sendStart()
        sendBurstTrigger += 1

        let id = UUID().uuidString
        demoTransferId = id

        // Durée dynamique : on garde une vitesse constante (686 px/s ≈ 240px/0.35s) peu importe
        // d'où le pouce a lâché. Sinon la trajectoire visuelle varie et le clip se désynchronise.
        let baseSpeed: CGFloat = 686
        let distance = abs(-240 - cloudDragY)
        let flightDuration = max(0.18, Double(distance / baseSpeed))

        // 0. Toute la page recule vers le haut (illusion "aspirée par le DI")
        withAnimation(.easeOut(duration: 0.35)) {
            pageScale = 0.94
            pageDim = 0.15
        }
        // Retour de la page après un moment
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.45)) {
            pageScale = 1
            pageDim = 0
        }
        // 1. Vol linéaire — vitesse constante peu importe la position de départ
        withAnimation(.linear(duration: flightDuration)) {
            cloudDragY = -240
        }
        // 2. Rétrécissement anisotrope IMMÉDIAT (easeOut = rapide dès le début, visible avant le clip DI)
        //    Largeur s'écrase fort, hauteur garde une trace → effet "goutte étirée / streak"
        withAnimation(.easeOut(duration: flightDuration)) {
            cloudScaleX = 0.08
            cloudScaleY = 0.35
            cloudScale = 0.2
        }
        // 2c. Motion blur qui monte avec la vitesse
        withAnimation(.easeOut(duration: flightDuration * 0.6)) {
            cloudBlur = 14
        }
        // Fade géré par cloudClipFactor (lié à cloudDragY) → frame-perfect avec le vol.
        PoofHaptics.impactMedium()

        // 4. Open the Dynamic Island right as the circle "arrives" — iOS
        //    handles the native bounce/expand animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + flightDuration + 0.03) {
            #if canImport(ActivityKit) && os(iOS)
                let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
                poofLog("[Poof] LiveActivities enabled = \(enabled)")
            #endif
            PoofLiveActivityController.shared.startSend(
                id: id,
                name: "Demo",
                total: 1,
                peerName: selectedDevice?.kind.displayName ?? "Device"
            )
            #if canImport(ActivityKit) && os(iOS)
                let count = Activity<PoofTransferAttributes>.activities.count
                poofLog("[Poof] Active activities after start = \(count)")
            #endif
            PoofHaptics.success()
        }

        // 5. End the demo activity after a few seconds & respawn the circle
        //    Séquence : (a) le cercle s'écrase à 0 en 0.28s pour clore l'envoi,
        //    (b) on reset l'icône à "cloud.fill" + on efface la sélection user
        //    (photo/file/clipboard) hors-écran, (c) il repop en spring bounce
        //    à taille pleine. Feedback visuel clair « envoi terminé, prêt à
        //    recommencer ».
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            PoofLiveActivityController.shared.endSend(id: id, success: true)

            // (a) implosion rapide du cercle
            withAnimation(.easeIn(duration: 0.28)) {
                cloudOpacity = 0
                cloudScale = 0.001
                cloudScaleX = 0.001
                cloudScaleY = 0.001
                cloudBlur = 0
            }

            // (b) reset state + respawn spring
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                selectedFiles = []
                selectedPhotos = []
                selectedPhotoImages = []
                clipboardPayload = nil
                cloudDragY = 0

                // Ferme le panel (rectangle glass) en même temps que le
                // centerIcon revient au cloud — sinon on garde un rectangle
                // vide (cloudPanelContent switch tombe sur EmptyView pour
                // "cloud.fill"). Animation coordonnée avec le respawn du
                // cercle central pour un reset global visuel propre.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    showCloudPanel = false
                    centerIcon = "cloud.fill"
                }

                // (c) spring bounce du cercle depuis 0 → 1 (subtle overshoot)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                    cloudScale = 1
                    cloudScaleX = 1
                    cloudScaleY = 1
                    cloudOpacity = 1
                }
                PoofHaptics.tap()
            }
        }
    }
}

// MARK: - Send burst particles

/// 12 particules blanches qui explosent en cercle depuis l'origine — se
/// dispersent + fade + shrink sur 0.65s. Re-déclenché à chaque incrément de
/// `trigger`. Positionnée à l'endroit du cercle par le parent.
private struct SendParticleBurst: View {
    let trigger: Int

    @State private var particles: [Particle] = SendParticleBurst.makeParticles()
    @State private var expanded: Bool = false

    struct Particle: Identifiable {
        let id = UUID()
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let delay: Double
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                ParticleDot(particle: p, expanded: expanded)
            }
        }
        .onChange(of: trigger) { _, _ in
            particles = Self.makeParticles()
            expanded = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                expanded = true
            }
        }
    }

    private struct ParticleDot: View {
        let particle: Particle
        let expanded: Bool

        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: particle.size, height: particle.size)
                .offset(x: expanded ? particle.dx : 0, y: expanded ? particle.dy : 0)
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 0.3 : 1)
                .shadow(color: .white.opacity(0.6), radius: 3)
                .animation(
                    .easeOut(duration: 0.65).delay(particle.delay),
                    value: expanded
                )
        }
    }

    private static func makeParticles() -> [Particle] {
        (0 ..< 12).map { i in
            let baseAngle = Double(i) * (.pi * 2 / 12)
            let jitter = Double.random(in: -0.15 ... 0.15)
            let angle = baseAngle + jitter
            let dist = CGFloat.random(in: 55 ... 85)
            return Particle(
                dx: cos(angle) * dist,
                dy: sin(angle) * dist,
                size: CGFloat.random(in: 3 ... 5),
                delay: Double.random(in: 0 ... 0.05)
            )
        }
    }
}

// MARK: - Clipboard payload

private enum ClipboardPayload {
    case text(String)
    case url(URL)
    case image(PoofImage)
}

// MARK: - Beta progress bar (pré-launch Premium)

/// Rectangle 320×100 qui remplace la bannière d'upsell Premium pendant la
/// beta. Affiche le compteur d'envois vs `PoofBetaCounter.targetCount` avec
/// une barre de progression animée. Communique la récompense : « 1 mois
/// Premium offert au lancement » quand l'utilisateur atteint le seuil.
private struct BetaProgressBar: View {
    @ObservedObject private var counter = PoofBetaCounter.shared

    /// Accent cyan → bleu Poof, réutilisé du cercle central Home + du hero
    /// orbit paywall. Sert de fill à la barre de progression pour rester
    /// dans l'identité visuelle de l'app.
    private static let accentGradient = LinearGradient(
        colors: [
            Color(red: 10 / 255, green: 226 / 255, blue: 255 / 255),
            Color(red: 0 / 255, green: 0 / 255, blue: 255 / 255)
        ],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        content
            .padding(.horizontal, 18)
            .frame(width: 320, height: 100)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        counter.isUnlocked ? Color.white.opacity(0.65) : Color.white.opacity(0.22),
                        lineWidth: counter.isUnlocked ? 1.4 : 0.8
                    )
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: counter.isUnlocked ? "gift.fill" : "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(counter.isUnlocked
                    ? L10n(fr: "1 mois Premium débloqué", en: "1 month Premium unlocked").localized
                    : L10n(fr: "Early supporter", en: "Early supporter").localized)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text("\(min(counter.sendCount, PoofBetaCounter.targetCount))/\(PoofBetaCounter.targetCount)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
            }
            progressBar
            Text(counter.isUnlocked
                ? L10n(
                    fr: "Récompense créditée automatiquement à la sortie du Premium.",
                    en: "Reward auto-granted when Premium launches."
                ).localized
                : L10n(
                    fr: "Envoie \(PoofBetaCounter.targetCount) fichiers → 1 mois Premium offert au lancement.",
                    en: "Send \(PoofBetaCounter.targetCount) files → 1 month Premium free at launch."
                ).localized)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Self.accentGradient)
                    .frame(width: max(4, geo.size.width * counter.progress))
                    .animation(.spring(response: 0.55, dampingFraction: 0.85), value: counter.progress)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Devices

enum DeviceKind: String, CaseIterable {
    case iphone, ipad, macbook

    var displayName: String {
        switch self {
        case .iphone: "iPhone"
        case .ipad: "iPad"
        case .macbook: "MacBook"
        }
    }

    var sfSymbol: String {
        switch self {
        case .iphone: "iphone.gen3"
        case .ipad: "ipad.gen2"
        case .macbook: "macbook.gen2"
        }
    }
}

struct PairedDevice: Equatable {
    let kind: DeviceKind
    var name: String?
    /// Identifiant du peer côté PoofSession — nil pour un slot manuel legacy.
    var peerId: String?
}

private struct DeviceBubble: View {
    let device: PairedDevice?
    let isSelected: Bool
    let onTap: () -> Void
    var onLongPress: (() -> Void)?

    @State private var isPressed = false
    @State private var isElevated = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
                .frame(width: 100, height: 100)
                .glassEffect(.regular.interactive(), in: Circle())

            if let device {
                Image(systemName: device.kind.sfSymbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .frame(width: 100, height: 100)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                .frame(width: 100, height: 100)
        )
        .contentShape(Circle())
        .scaleEffect(isPressed ? 1.08 : (isSelected ? 1.04 : 1.0))
        .zIndex(isElevated ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isSelected)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        isElevated = true
                        PoofHaptics.tap()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onTap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isElevated = false
                    }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    onLongPress?()
                }
        )
    }
}

/// ButtonStyle qui laisse passer les swipes horizontaux vers un parent ScrollView,
/// mais donne un feedback visuel de press (contrairement à DragGesture qui vole tout).
private struct PressBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct GlassChip: View {
    let icon: String?
    let action: () -> Void
    @State private var isPressed = false
    @State private var isElevated = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
                .frame(width: 100, height: 100)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
        }
        .frame(width: 100, height: 100)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(isPressed ? 1.08 : 1.0)
        .zIndex(isElevated ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        isElevated = true
                        PoofHaptics.tap()
                        action()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isElevated = false
                    }
                }
        )
    }
}

#Preview {
    TabView {
        PoofSendView(
            onOpenSendSheet: {},
            onOpenPairing: {}
        )
        .tabItem { Label("Send", systemImage: "paperplane.fill") }

        Color.clear
            .tabItem { Label("Home", systemImage: "house.fill") }
    }
    .environmentObject(PoofSession())
    .preferredColorScheme(.dark)
}
