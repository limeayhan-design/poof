import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

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

    private var tier: PoofTier { PoofTier(rawValue: tierRaw) ?? .free }
    private var atPairingLimit: Bool {
        guard let max = tier.maxPairedDevices else { return false }
        return session.peers.peers.count >= max
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if atPairingLimit {
                            pairingLimitBanner
                            Divider().background(PoofTheme.glassStroke)
                        } else {
                            addDeviceBlock
                            Divider().background(PoofTheme.glassStroke)
                            joinBlock
                            Divider().background(PoofTheme.glassStroke)
                        }
                        renameBlock
                        Divider().background(PoofTheme.glassStroke)
                        signalingBlock
                        Divider().background(PoofTheme.glassStroke)
                        debugBlock
                        Divider().background(PoofTheme.glassStroke)
                        HStack {
                            Button {
                                showHistory = true
                            } label: {
                                Label("History", systemImage: "clock.arrow.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(PoofTheme.textPrimary)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .glassCard()
                            }
                            Spacer()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(PoofTheme.accent)
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
                if session.pairCode == nil && !atPairingLimit { session.requestPairCode() }
            }
        }
    }

    // MARK: - Limit banner

    private var pairingLimitBanner: some View {
        let count = session.peers.peers.count
        let limit = tier.maxPairedDevices ?? count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tier.accent)
                Text("Device limit reached")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                Spacer()
                Text("\(count)/\(limit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tier.accent)
            }
            Text("\(tier.displayName) allows \(tier.pairingLimitLabel). Upgrade for unlimited pairings, or unpair a device from the home screen.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showPricing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("Upgrade")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [tier.accent, tier.glow],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusMd)
        .overlay(
            RoundedRectangle(cornerRadius: PoofTheme.radiusMd)
                .strokeBorder(tier.accent.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Add a device (QR + code + fallback)

    private var addDeviceBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a device")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(PoofTheme.textPrimary)
            Text("Scan this QR from the other device, or type the code.")
                .font(.system(size: 13))
                .foregroundColor(PoofTheme.textSecondary)

            let payload = pairURL()
            if let img = generateQR(payload) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 10) {
                ForEach(codeDigits(), id: \.self) { d in
                    Text(d)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(PoofTheme.textPrimary)
                        .frame(width: 34, height: 44)
                        .glassCard(radius: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if session.pairCode != nil {
                Text("Or open \(hostURL()) on your phone")
                    .font(.system(size: 12))
                    .foregroundColor(PoofTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 10) {
                Button {
                    session.cancelPair()
                    session.requestPairCode()
                } label: {
                    Label("New code", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassCard()
                }
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(PoofTheme.accent))
                }
            }
        }
    }

    private var joinBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or type a code from another device")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            HStack(spacing: 8) {
                TextField("ABCDEF", text: $joinCode)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(PoofTheme.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .glassCard()
                Button("Pair") {
                    let code = joinCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !code.isEmpty {
                        session.joinWithCode(code)
                        joinCode = ""
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Capsule().fill(PoofTheme.accent))
            }
            if let err = session.pairError {
                Text(err).font(.system(size: 12)).foregroundColor(PoofTheme.danger)
            }
        }
    }

    private var renameBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This device")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            HStack(spacing: 8) {
                TextField("Device name", text: $nameField)
                    .font(.system(size: 15))
                    .foregroundColor(PoofTheme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .glassCard()
                Button("Rename") {
                    PoofDeviceIdentity.name = nameField
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Capsule().fill(PoofTheme.accent))
            }
        }
    }

    private var signalingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signaling server")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            Text("URL of your Poof relay (e.g. http://192.168.1.42:3000).")
                .font(.system(size: 12)).foregroundColor(PoofTheme.textTertiary)
            HStack(spacing: 8) {
                TextField("http://…", text: $signalingField)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(PoofTheme.textPrimary)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .glassCard()
                Button("Save") {
                    if let url = PoofOnboardingSheet.parseURL(signalingField) {
                        session.updateSignalingURL(url)
                        dismiss()
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Capsule().fill(PoofTheme.accent))
            }
        }
    }

    // MARK: - Debug

    private var debugBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PoofTheme.textPrimary)
            debugRow("This device", PoofDeviceIdentity.deviceId)
            debugRow("Signaling", session.isSignalingConnected ? "connected" : "disconnected")
            debugRow("Paired IDs", session.peers.ids.joined(separator: "\n") .ifEmpty("—"))
            debugRow("Online IDs", Array(session.onlinePeerIds).joined(separator: "\n").ifEmpty("—"))
            debugRow("Active peer", session.activePeerId ?? "—")
            HStack {
                Button {
                    UIPasteboard.general.string = debugPayload()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PoofTheme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassCard(radius: 12)
                }
                Spacer()
            }
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PoofTheme.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(PoofTheme.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
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

extension String {
    fileprivate func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> QRScannerVC {
        let vc = QRScannerVC()
        vc.onCode = { code in context.coordinator.emit(code) }
        return vc
    }
    func updateUIViewController(_ vc: QRScannerVC, context: Context) {}

    final class Coordinator {
        let onCode: (String) -> Void
        var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
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
        if !session.isRunning { DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() } }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        onCode?(str)
    }
}
