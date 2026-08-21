import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

// Settings + pairing sheet — mirrors the pair modal in pc/index.html:
//   QR + pair code + fallback URL + join field + rename + history entry.

struct PairingSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue
    @State private var joinCode: String = ""
    @State private var nameField: String = PoofDeviceIdentity.name
    @State private var signalingField: String = PoofSession.signalingURL.absoluteString
    @State private var showScanner = false
    @State private var showHistory = false
    @State private var showPricing = false

    private var tier: PoofTier {
        PoofTier(rawValue: tierRaw) ?? .free
    }

    private var atPairingLimit: Bool {
        guard let max = tier.maxPairedDevices else { return false }
        return session.peers.peers.count >= max
    }

    var body: some View {
        ZStack {
            PoofBackground()

            VStack(spacing: 0) {
                sheetNavBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if atPairingLimit {
                            pairingLimitBanner.appleEntry(delay: 0.05)
                        } else {
                            addDeviceBlock.appleEntry(delay: 0.05)
                            joinBlock.appleEntry(delay: 0.12)
                        }
                        renameBlock.appleEntry(delay: 0.19)
                        signalingBlock.appleEntry(delay: 0.26)
                        historyLink.appleEntry(delay: 0.33)
                        debugBlock.appleEntry(delay: 0.40)
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                guard !atPairingLimit else {
                    session.pairError = "Device limit reached. Upgrade or unpair one."
                    return
                }
                let extracted = Self.extractPairCode(from: code)
                session.joinWithCode(extracted)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet().environmentObject(session)
        }
        .sheet(isPresented: $showPricing) {
            PricingSheet()
        }
        .onAppear {
            if session.pairCode == nil, !atPairingLimit {
                session.requestPairCode()
            }
        }
    }

    // MARK: - Custom nav bar (matches PoofRootView chrome)

    private var sheetNavBar: some View {
        HStack {
            Color.clear.frame(width: 34, height: 34)
            Spacer()
            Text("Pair a device")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var historyLink: some View {
        Button {
            PoofHaptics.tap()
            showHistory = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 36, height: 36)

                Text("Activity history")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Limit banner

    private var pairingLimitBanner: some View {
        let count = session.peers.peers.count
        let limit = tier.maxPairedDevices ?? count
        return sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(tier.accent)
                    Text("Device limit reached")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(count)/\(limit)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tier.accent)
                }
                Text(
                    "\(tier.displayName) allows \(tier.pairingLimitLabel). Upgrade for unlimited pairings, or unpair a device from the home screen."
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                Button { showPricing = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("Upgrade")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [tier.accent, tier.glow],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: tier.accent.opacity(0.5), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Add a device (QR + code + fallback) — hero block

    private var addDeviceBlock: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Add a device", subtitle: "Scan this QR from the other device, or type the code below.")

                qrHero
                    .frame(maxWidth: .infinity, alignment: .center)

                digitsStrip
                    .frame(maxWidth: .infinity, alignment: .center)

                if session.pairCode != nil {
                    Text("Or open \(hostURL()) on your phone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                HStack(spacing: 10) {
                    softPill(icon: "arrow.clockwise", label: "New code") {
                        session.cancelPair()
                        session.requestPairCode()
                    }
                    primaryPill(icon: "qrcode.viewfinder", label: "Scan QR") {
                        showScanner = true
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var qrHero: some View {
        ZStack {
            AppleRadialGlow(color: PoofTheme.cyanGlow, intensity: 0.28)
                .frame(width: 260, height: 260)

            let payload = pairURL()
            if let img = generateQR(payload) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            }
        }
    }

    private var digitsStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(codeDigits().enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.7
                            )
                    )
            }
        }
    }

    // MARK: - Other blocks

    private var joinBlock: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Or paste a code", subtitle: "From another device — 6 characters.")
                HStack(spacing: 10) {
                    inputField(
                        text: $joinCode,
                        placeholder: "ABCDEF",
                        isMono: true,
                        autocap: .characters
                    )
                    primaryPillCompact(label: "Pair") {
                        let code = joinCode.uppercased()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !code.isEmpty {
                            session.joinWithCode(code)
                            joinCode = ""
                        }
                    }
                }
                if let err = session.pairError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PoofTheme.danger)
                }
            }
        }
    }

    private var renameBlock: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("This device", subtitle: "The name other devices will see.")
                HStack(spacing: 10) {
                    inputField(text: $nameField, placeholder: "Device name")
                    primaryPillCompact(label: "Save") {
                        PoofDeviceIdentity.name = nameField
                    }
                }
            }
        }
    }

    private var signalingBlock: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    "Signaling server",
                    subtitle: "URL of your Poof relay, e.g. http://192.168.1.42:3000."
                )
                HStack(spacing: 10) {
                    inputField(
                        text: $signalingField,
                        placeholder: "http://…",
                        isMono: true,
                        autocap: .never,
                        keyboard: .URL
                    )
                    primaryPillCompact(label: "Save") {
                        if let url = PoofOnboardingSheet.parseURL(signalingField) {
                            session.updateSignalingURL(url)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Debug

    private var debugBlock: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Debug", subtitle: nil)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = debugPayload()
                        PoofHaptics.tap()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                    }
                }
                debugRow("This device", PoofDeviceIdentity.deviceId)
                debugRow("Signaling", session.isSignalingConnected ? "connected" : "disconnected")
                debugRow("Paired IDs", session.peers.ids.joined(separator: "\n").ifEmpty("—"))
                debugRow("Online IDs", Array(session.onlinePeerIds).joined(separator: "\n").ifEmpty("—"))
                debugRow("Active peer", session.activePeerId ?? "—")
            }
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.45))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.85))
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Shared building blocks

    private func sectionCard(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            )
            .appleRimHighlight(radius: 22, top: 0.22, mid: 0.03)
    }

    private func sectionTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inputField(
        text: Binding<String>,
        placeholder: String,
        isMono: Bool = false,
        autocap: TextInputAutocapitalization = .sentences,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        TextField(placeholder, text: text)
            .font(isMono
                ? .system(size: 15, weight: .semibold, design: .monospaced)
                : .system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(autocap)
            .keyboardType(keyboard)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            )
    }

    private func primaryPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [PoofTheme.blueStart, PoofTheme.blueEnd],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
            )
            .shadow(color: PoofTheme.blueStart.opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func softPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func primaryPillCompact(label: String, action: @escaping () -> Void) -> some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [PoofTheme.blueStart, PoofTheme.blueEnd],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )
                .shadow(color: PoofTheme.blueStart.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func debugPayload() -> String {
        """
        deviceId: \(PoofDeviceIdentity.deviceId)
        signaling: \(session.isSignalingConnected ? "up" : "down") \(PoofSession.signalingURL.absoluteString)
        paired: \(session.peers.ids)
        online: \(Array(session.onlinePeerIds))
        active: \(session.activePeerId ?? "-")
        """
    }

    // MARK: - Helpers

    private func codeDigits() -> [String] {
        let raw = session.pairCode ?? "——————"
        return raw.map { String($0) }
    }

    private func hostURL() -> String {
        PoofSession.signalingURL.host.map { "http://\($0):\(PoofSession.signalingURL.port ?? 3000)" }
            ?? PoofSession.signalingURL.absoluteString
    }

    private func pairURL() -> String {
        guard let code = session.pairCode else { return hostURL() }
        return "\(hostURL())/#pair=\(code)"
    }

    private func generateQR(_ text: String) -> UIImage? {
        let ctx = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func extractPairCode(from raw: String) -> String {
        if let range = raw.range(of: "#pair=") {
            return String(raw[range.upperBound...])
                .components(separatedBy: CharacterSet(charactersIn: "&?/ "))
                .first?
                .uppercased() ?? raw
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> QRScannerVC {
        let vc = QRScannerVC()
        vc.onCode = { code in context.coordinator.emit(code) }
        return vc
    }

    func updateUIViewController(_: QRScannerVC, context _: Context) {}

    final class Coordinator {
        let onCode: (String) -> Void
        var fired = false
        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func emit(_ c: String) {
            guard !fired else { return }
            fired = true
            onCode(c)
        }
    }
}

final class QRScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        onCode?(str)
    }
}
