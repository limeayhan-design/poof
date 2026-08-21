import AVKit
import SwiftUI

#if canImport(UIKit)
    import Photos
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

/// Sheet fullscreen cross-platform pour l'ouverture d'un fichier reçu.
/// - Applique toutes les gates Secure (expiry, biometrics, passcode, one-time).
/// - Affiche le message Track custom.
/// - Overlaie le watermark quand Secure le prévoit (indélébile côté UI).
/// - Preview image / vidéo / générique + boutons Save + Share.
/// - Screenshot alert observer côté iOS (Mac : API publique manquante).
struct PoofReceivedFileSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var toastText: String?
    @State private var secureGate: SecureGateState = .checking
    @State private var showPasscodePrompt = false
    @State private var showShare = false

    /// État du gate Secure — l'utilisateur ne voit le contenu qu'en `.unlocked`.
    enum SecureGateState: Equatable {
        case checking
        case unlocked
        case awaitingPasscode(expected: String)
        case awaitingBiometric
        case expired
        case denied

        var isUnlocked: Bool {
            self == .unlocked
        }
    }

    private var entry: PoofSession.ReceivedFile? {
        session.receivedFiles.first(where: { $0.url == url })
    }

    private var secureConfig: SecureConfig? {
        entry?.secureConfig
    }

    var body: some View {
        ZStack {
            background

            if secureGate.isUnlocked || secureConfig == nil {
                unlockedContent
                    .overlay(watermarkOverlay)
            } else {
                secureGateView
            }

            if let toast = toastText {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar.padding(.horizontal, 20).padding(.top, 24)
        }
        .sheet(isPresented: $showPasscodePrompt) {
            if case let .awaitingPasscode(expected) = secureGate {
                PasscodePromptSheet(
                    expectedCode: expected,
                    onUnlock: {
                        showPasscodePrompt = false
                        secureGate = .unlocked
                        if let id = entry?.id {
                            session.markSecureOpened(id)
                        }
                    },
                    onCancel: {
                        showPasscodePrompt = false
                        secureGate = .denied
                        dismiss()
                    }
                )
                .interactiveDismissDisabled(true)
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [exportURL()])
        }
        #endif
        .onAppear {
            if let e = entry {
                poofLog(
                    "[Poof] Sheet.onAppear — file=\(e.name) id=\(e.id) hasTrack=\(e.trackConfig != nil)"
                )
                session.markSeen(e.id, kind: .opened)
                // Pré-warm Face ID/Touch ID SI ce fichier va le demander —
                // réduit la latence du prompt de ~300ms (iOS charge les
                // modèles + init caméra en parallèle du rendu de la sheet).
                if e.secureConfig?.biometrics == true {
                    SecureBiometrics.prewarm()
                }
            } else {
                poofLog("[Poof] Sheet.onAppear — entry nil (URL not in receivedFiles)")
            }
            evaluateSecureGate()
        }
        .onDisappear {
            enforceOneTimeViewOnClose()
        }
    }

    // MARK: - Background

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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                PoofHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Unlocked content (preview + meta + actions)

    private var unlockedContent: some View {
        VStack(spacing: 14) {
            if let expiry = entry?.expiryDate {
                expiryTimerBadge(expiry)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            if entry?.secureConfig?.oneTimeView == true {
                oneTimeViewBadge
                    .padding(.horizontal, 16)
                    .padding(.top, entry?.expiryDate == nil ? 6 : 0)
            }
            if let msg = entry?.trackConfig?.customMessage, !msg.isEmpty {
                trackMessageBanner(msg)
                    .padding(.horizontal, 16)
                    .padding(.top, entry?.expiryDate == nil ? 6 : 0)
            }
            preview
                .padding(.horizontal, 16)
                .padding(.top, 4)
            Spacer(minLength: 12)
            metaCard.padding(.horizontal, 16)
            actionRow.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 20)
        }
    }

    /// Badge visible qui prévient l'utilisateur que ce fichier va être
    /// supprimé dès la fermeture de la sheet (one-time view). Complète
    /// le contrat visuel — sans ce badge, la disparition serait un « effet
    /// magique » incompréhensible.
    private var oneTimeViewBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
            Text(L10n(
                fr: "Ouverture unique — se supprime à la fermeture",
                en: "One-time view — deletes on close"
            ).localized)
                .font(.system(size: 12, weight: .heavy))
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.85, green: 0.35, blue: 0.25).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
        )
    }

    /// Badge countdown live — refresh chaque seconde via TimelineView.
    /// Passe orange puis rouge quand l'expiry approche. À l'expiration
    /// le fichier est purgé automatiquement par le sweeper 60s + le check
    /// à l'onAppear (evaluateSecureGate check `entry.isExpired`).
    private func expiryTimerBadge(_ expiryDate: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = expiryDate.timeIntervalSince(context.date)
            let tint = expiryTint(remaining: remaining)
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(remaining <= 0
                    ? L10n(fr: "Expiré", en: "Expired").localized
                    : L10n(
                        fr: "Expire dans \(formatRemaining(remaining))",
                        en: "Expires in \(formatRemaining(remaining))"
                    ).localized)
                    .font(.system(size: 12, weight: .heavy))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
            )
        }
    }

    /// Formatage humain adaptatif : "45s", "12m 34s", "2h 15m", "3j 7h".
    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 {
            return "\(s)s"
        }
        if s < 3600 {
            let m = s / 60
            let rem = s % 60
            return "\(m)m \(rem)s"
        }
        if s < 86400 {
            let h = s / 3600
            let m = (s % 3600) / 60
            return "\(h)h \(m)m"
        }
        let d = s / 86400
        let h = (s % 86400) / 3600
        return "\(d)j \(h)h"
    }

    /// Couleur du badge — vert calme si loin, orange si < 1h, rouge < 5min.
    private func expiryTint(remaining: TimeInterval) -> Color {
        if remaining <= 300 {
            return Color(red: 0.85, green: 0.25, blue: 0.25)
        }
        if remaining <= 3600 {
            return Color(red: 0.95, green: 0.55, blue: 0.20)
        }
        return Color(red: 0.20, green: 0.55, blue: 0.35)
    }

    private func trackMessageBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
        )
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if isVideoExtension {
            VideoPlayer(player: AVPlayer(url: url))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        } else if isImageExtension {
            // Chargement direct du file:// URL — AsyncImage échoue souvent sur
            // les fichiers locaux (bug SwiftUI connu), on passe par PoofImage
            // (UIImage/NSImage) qui accepte n'importe quel path.
            if let img = loadLocalImage(url) {
                Image(poofImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            } else {
                genericPreview
            }
        } else {
            genericPreview
        }
    }

    private var imageLoadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                ProgressView()
                    .tint(.white.opacity(0.7))
            )
            .frame(maxWidth: .infinity, minHeight: 340)
    }

    private var isImageExtension: Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp"].contains(ext)
    }

    /// Charge un fichier image local — 2 stratégies en cascade :
    /// 1. `PoofImage(contentsOfFile:)` (Mac NSImage / iOS UIImage) natif, le
    ///    plus fiable pour les file:// URLs locaux
    /// 2. `Data(contentsOf:)` + `PoofImage(data:)` fallback
    private func loadLocalImage(_ url: URL) -> PoofImage? {
        #if canImport(AppKit)
            if let img = NSImage(contentsOf: url) {
                return img
            }
        #elseif canImport(UIKit)
            if let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        #endif
        guard let data = try? Data(contentsOf: url) else {
            poofLog("[Poof] loadLocalImage: file read failed @ \(url.path)")
            return nil
        }
        guard let img = PoofImage(data: data) else {
            poofLog("[Poof] loadLocalImage: decode failed for \(data.count) bytes @ \(url.path)")
            return nil
        }
        return img
    }

    private var isVideoExtension: Bool {
        let ext = url.pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "hevc", "avi", "mkv"].contains(ext)
    }

    private var genericPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                )

            VStack(spacing: 16) {
                Image(systemName: genericIcon)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                Text(url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                #if DEBUG
                    debugFileInfo
                #endif
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    /// DEBUG-only : affiche exists / size / magic bytes pour diagnostiquer
    /// pourquoi la preview image tombe sur genericPreview.
    /// - Absent → fichier supprimé par decrypt failed
    /// - Size 0 → écriture pas finie
    /// - Magic FFD8 → JPEG valide (bug loadLocalImage)
    /// - Magic autre → encore chiffré (bug decrypt skip)
    private var debugFileInfo: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var magic = "—"
        if exists, let fh = try? FileHandle(forReadingFrom: url) {
            let head = fh.readData(ofLength: 4)
            try? fh.close()
            magic = head.map { String(format: "%02X", $0) }.joined()
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.orange)
            Text("exists: \(exists)").font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
            Text("size: \(size) B").font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
            Text("magic: \(magic)").font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
            Text("secureCfg: \(secureConfig == nil ? "nil" : "yes")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
    }

    // MARK: - Meta card + action row

    private var metaCard: some View {
        HStack(spacing: 12) {
            Image(systemName: genericIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
    }

    private var actionRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if canSave {
                    actionButton(icon: "square.and.arrow.down", label: "Save", primary: true) {
                        saveFile()
                    }
                }
                if canShare {
                    actionButton(icon: "square.and.arrow.up", label: "Share", primary: !canSave) {
                        #if canImport(UIKit)
                            showShare = true
                        #elseif canImport(AppKit)
                            macShare()
                        #endif
                    }
                }
            }
            if secureConfig != nil {
                secureSaveNotice
            }
        }
    }

    /// Petit bandeau info affiché à la place du bouton Save quand un
    /// expiry est actif — explique pourquoi Save et Share sont désactivés
    /// (contrainte technique iOS + protection promesse Secure).
    private var secureSaveNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 1)
            Text(L10n(
                fr: "Sauvegarde et partage désactivés : ce fichier doit disparaître à l'expiration.",
                en: "Save and share disabled: this file must vanish at expiration."
            ).localized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
    }

    /// Share autorisé sauf pour les envois `oneTimeView` (destinés à
    /// disparaître). Si watermark actif → l'image partagée est gravée.
    private var canShare: Bool {
        if secureConfig?.oneTimeView == true {
            return false
        }
        return true
    }

    private func actionButton(icon: String, label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(primary ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(primary ? Color.white : Color.white.opacity(0.14))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(primary ? 0.4 : 0.20), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secure gate

    private func evaluateSecureGate() {
        guard let config = secureConfig else {
            secureGate = .unlocked
            return
        }
        if entry?.isExpired == true {
            secureGate = .expired
            if let id = entry?.id {
                session.purgeReceivedFile(id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { dismiss() }
            return
        }
        if config.biometrics {
            secureGate = .awaitingBiometric
            Task {
                let ok = await SecureBiometrics.evaluate(
                    reason: L10n(
                        fr: "Authentification requise pour ouvrir ce fichier.",
                        en: "Authentication required to open this file."
                    ).localized
                )
                await MainActor.run {
                    if ok {
                        if case let .digits(code) = config.passcode, !code.isEmpty {
                            secureGate = .awaitingPasscode(expected: code)
                            showPasscodePrompt = true
                        } else {
                            secureGate = .unlocked
                            if let id = entry?.id {
                                session.markSecureOpened(id)
                            }
                        }
                    } else {
                        secureGate = .denied
                        dismiss()
                    }
                }
            }
            return
        }
        if case let .digits(code) = config.passcode, !code.isEmpty {
            secureGate = .awaitingPasscode(expected: code)
            showPasscodePrompt = true
            return
        }
        secureGate = .unlocked
        if let id = entry?.id {
            session.markSecureOpened(id)
        }
    }

    private var secureGateView: some View {
        VStack(spacing: 20) {
            Image(systemName: gateIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white)
                .padding(28)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
            Text(gateTitle)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(gateSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
        }
    }

    private var gateIcon: String {
        switch secureGate {
        case .expired: "clock.badge.xmark"
        case .denied: "lock.slash.fill"
        case .awaitingBiometric: "faceid"
        default: "lock.shield.fill"
        }
    }

    private var gateTitle: String {
        switch secureGate {
        case .expired: L10n(fr: "Fichier expiré", en: "File expired").localized
        case .denied: L10n(fr: "Accès refusé", en: "Access denied").localized
        case .awaitingBiometric: L10n(fr: "Authentification…", en: "Authenticating…").localized
        default: L10n(fr: "Fichier protégé", en: "Protected file").localized
        }
    }

    private var gateSubtitle: String {
        switch secureGate {
        case .expired:
            L10n(
                fr: "L'expéditeur a fixé une durée de vie. Ce fichier a été supprimé automatiquement.",
                en: "The sender set a lifetime. This file was auto-deleted."
            ).localized
        case .denied:
            L10n(
                fr: "Cet envoi Secure est protégé et n'a pas pu être déverrouillé.",
                en: "This Secure send is protected and could not be unlocked."
            ).localized
        case .awaitingBiometric:
            L10n(
                fr: "Utilise Face ID ou Touch ID pour continuer.",
                en: "Use Face ID or Touch ID to continue."
            ).localized
        default:
            L10n(fr: "Vérification en cours…", en: "Verifying…").localized
        }
    }

    // MARK: - Watermark overlay

    @ViewBuilder
    private var watermarkOverlay: some View {
        if let watermark = watermarkText {
            GeometryReader { geo in
                ForEach(0 ..< 5, id: \.self) { i in
                    Text(watermark)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.14))
                        .rotationEffect(.degrees(-24))
                        .position(
                            x: geo.size.width * CGFloat.random(in: 0.15 ... 0.85),
                            y: geo.size.height * CGFloat(i + 1) / 6.0
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var watermarkText: String? {
        switch secureConfig?.watermark {
        case .off, .none: return nil
        case .recipientName:
            #if canImport(UIKit)
                return UIDevice.current.name
            #elseif canImport(AppKit)
                return Host.current().localizedName ?? "Mac"
            #else
                return "Poof"
            #endif
        case let .custom(text): return text.isEmpty ? nil : text
        }
    }

    // MARK: - One-time view enforcement

    private func enforceOneTimeViewOnClose() {
        guard let e = entry,
              let config = e.secureConfig,
              config.oneTimeView,
              e.openedAt != nil
        else {
            return
        }
        poofLog("[Poof] One-time view — purging \(e.name)")
        session.purgeReceivedFile(e.id)
        session.toast = "Deleted (one-time view)"
    }

    // MARK: - Save / Share

    private var canSave: Bool {
        // Save autorisé sauf pour les envois `oneTimeView` (le contrat impose
        // qu'ils disparaissent à la fermeture). Sinon on autorise, mais si
        // watermark actif on grave le texte dans l'image exportée pour que la
        // fuite reste traçable.
        if secureConfig?.oneTimeView == true {
            return false
        }
        return isImageExtension || isVideoExtension
    }

    /// Retourne l'URL à utiliser pour Save/Share. Si watermark actif ET image,
    /// génère un fichier temporaire avec le watermark gravé dessus. Sinon
    /// retourne l'URL originale.
    private func exportURL() -> URL {
        guard let text = watermarkText, isImageExtension else { return url }
        guard let img = loadLocalImage(url) else { return url }
        guard let watermarked = imageWithBurnedWatermark(img, text: text) else { return url }
        let tempName = "PoofWM-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(tempName)
        guard let data = watermarked.poofPNGData else { return url }
        try? data.write(to: temp)
        return temp
    }

    /// Grave le texte watermark en diagonale répété sur l'image, avec
    /// opacité 0.35 blanc. Résultat visible mais lisible du contenu.
    private func imageWithBurnedWatermark(_ img: PoofImage, text: String) -> PoofImage? {
        #if canImport(UIKit)
            let size = img.size
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                img.draw(in: CGRect(origin: .zero, size: size))
                let fontSize = max(20, size.width / 30)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.35)
                ]
                let attrText = NSAttributedString(string: text, attributes: attrs)
                let textSize = attrText.size()
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.rotate(by: -.pi / 6)
                cg.translateBy(x: -size.width / 2, y: -size.height / 2)
                let stepY = max(textSize.height * 3, size.height / 5)
                let stepX = textSize.width + 60
                var y: CGFloat = -textSize.height
                while y < size.height + textSize.height {
                    var x: CGFloat = -textSize.width
                    while x < size.width + stepX {
                        attrText.draw(at: CGPoint(x: x, y: y))
                        x += stepX
                    }
                    y += stepY
                }
                cg.restoreGState()
            }
        #elseif canImport(AppKit)
            let size = img.size
            let out = NSImage(size: size)
            out.lockFocus()
            img.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = max(20, size.width / 30)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.35)
            ]
            let attrText = NSAttributedString(string: text, attributes: attrs)
            let textSize = attrText.size()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: -.pi / 6)
                ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                let stepY = max(textSize.height * 3, size.height / 5)
                let stepX = textSize.width + 60
                var y: CGFloat = -textSize.height
                while y < size.height + textSize.height {
                    var x: CGFloat = -textSize.width
                    while x < size.width + stepX {
                        attrText.draw(at: CGPoint(x: x, y: y))
                        x += stepX
                    }
                    y += stepY
                }
                ctx.restoreGState()
            }
            out.unlockFocus()
            return out
        #else
            return nil
        #endif
    }

    private func saveFile() {
        // exportURL renvoie l'URL originale ou une copie temp avec watermark
        // gravé dans l'image si Secure watermark est actif.
        let source = exportURL()
        #if canImport(UIKit)
            // .readWrite (au lieu de .addOnly) car on doit pouvoir supprimer
            // la copie galerie à l'expiration Secure — sinon la promesse
            // « auto-destruct » serait bypass par un Save vers Photos.
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { flash("Photos access denied") }
                    return
                }
                var createdIdentifier: String?
                PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let type: PHAssetResourceType = isVideoExtension ? .video : .photo
                    req.addResource(with: type, fileURL: source, options: nil)
                    createdIdentifier = req.placeholderForCreatedAsset?.localIdentifier
                } completionHandler: { ok, _ in
                    DispatchQueue.main.async {
                        if ok, let identifier = createdIdentifier, let id = entry?.id {
                            session.recordSavedAsset(id: identifier, for: id)
                        }
                        flash(ok ? "Saved to Photos" : "Save failed")
                    }
                }
            }
        #elseif canImport(AppKit)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = source.lastPathComponent
            panel.canCreateDirectories = true
            panel.title = "Save file"
            let response = panel.runModal()
            guard response == .OK, let dest = panel.url else { return }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: source, to: dest)
                flash("Saved to \(dest.deletingLastPathComponent().lastPathComponent)")
            } catch {
                flash("Save failed: \(error.localizedDescription)")
            }
        #endif
    }

    #if canImport(AppKit)
        private func macShare() {
            let picker = NSSharingServicePicker(items: [exportURL()])
            if let window = NSApplication.shared.keyWindow,
               let contentView = window.contentView
            {
                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
        }
    #endif

    private func flash(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if toastText == text {
                withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
            }
        }
    }

    // MARK: - Kind detection

    private var genericIcon: String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) {
            return "photo.fill"
        }
        if ["mp4", "mov", "m4v"].contains(ext) {
            return "film.fill"
        }
        if ["pdf"].contains(ext) {
            return "doc.richtext.fill"
        }
        if ["txt", "md"].contains(ext) {
            return "doc.text.fill"
        }
        return "doc.fill"
    }

    private var sizeText: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - ShareSheet iOS wrapper

#if canImport(UIKit)
    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }
#endif
