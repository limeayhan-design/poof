import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

import AVFoundation

// Sheet "Add a device" — remplace le confirmationDialog mock iPhone/iPad/MacBook.
// 3 méthodes : à proximité (auto-détection), scan QR, invitation SMS/mail, code manuel.
// Le "My QR" en haut à droite laisse l'autre partie scanner ce device.

struct PoofAddDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: PoofSession

    @StateObject private var nearby = NearbyPeerStore()
    @State private var showQRScanner = false
    @State private var showMyQR = false
    @State private var showInvite = false
    @State private var showCodeEntry = false
    @State private var pairFailure: String?

    let onPair: (PairedDevice) -> Void

    var body: some View {
        NavigationStack {
            List {
                nearbySection
                remoteSection
            }
            .poofInsetListStyle()
            .navigationTitle("Add a device")
            .poofInlineNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMyQR = true
                    } label: {
                        Label("My QR", systemImage: "qrcode")
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { scanned in
                    handleScannedCode(scanned)
                    showQRScanner = false
                }
            }
            .sheet(isPresented: $showMyQR) {
                MyQRSheet().environmentObject(session)
            }
            .alert("Pairing failed", isPresented: Binding(
                get: { pairFailure != nil },
                set: {
                    if !$0 {
                        pairFailure = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { pairFailure = nil }
            } message: {
                Text(pairFailure ?? "")
            }
            .sheet(isPresented: $showInvite) {
                InviteSheet(url: nearby.myInviteURL)
            }
            .sheet(isPresented: $showCodeEntry) {
                CodeEntrySheet { code in
                    handleScannedCode(code)
                    showCodeEntry = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { nearby.start() }
        .onDisappear { nearby.stop() }
    }

    // MARK: - Sections

    /// Peers découverts filtrés : on retire ceux déjà présents dans le
    /// `PoofPeerStore` — inutile de proposer d'appairer un device déjà lié.
    private var nearbyFiltered: [NearbyPeer] {
        let paired = Set(session.peers.ids)
        return nearby.peers.filter { !paired.contains($0.id) }
    }

    private var nearbySection: some View {
        Section {
            if nearbyFiltered.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().tint(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching for devices…")
                            .font(.callout)
                        Text("Make sure Poof is open on both sides.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(nearbyFiltered) { peer in
                    Button {
                        pairNearby(peer)
                    } label: {
                        nearbyRow(peer)
                    }
                    .foregroundColor(.primary)
                }
            }
        } header: {
            HStack {
                Text("Nearby")
                Spacer()
                if !nearbyFiltered.isEmpty {
                    Text("\(nearbyFiltered.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var remoteSection: some View {
        Section("Add remotely") {
            methodRow(
                icon: "qrcode.viewfinder",
                title: "Scan a QR code",
                subtitle: "From another iPhone, iPad or computer"
            ) { showQRScanner = true }

            methodRow(
                icon: "paperplane.fill",
                title: "Send an invitation",
                subtitle: "Via iMessage, SMS or email"
            ) { showInvite = true }

            methodRow(
                icon: "number",
                title: "Enter a code",
                subtitle: "6 characters shared verbally"
            ) { showCodeEntry = true }
        }
    }

    // MARK: - Rows

    private func nearbyRow(_ peer: NearbyPeer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: peer.kind.sfSymbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.body)
                Text(peer.kind.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Pair")
                .font(.footnote.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.blue))
        }
    }

    private func methodRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func pairNearby(_ peer: NearbyPeer) {
        // Envoie une invite MC au device distant — sa sheet accept/deny
        // s'affiche. À l'acceptation, `PoofSession.onPairingComplete`
        // ajoute le peer aux 2 côtés et ouvre la session WebRTC.
        nearby.invite(peer)
        dismiss()
    }

    private func handleScannedCode(_ raw: String) {
        poofLog("[Poof] handleScannedCode — raw=\(raw)")
        guard let code = Self.extractPairCode(from: raw) else {
            poofLog("[Poof] handleScannedCode — extractPairCode returned nil for raw=\(raw)")
            pairFailure = "Invalid pairing code (raw: \(raw.prefix(50)))"
            return
        }
        poofLog("[Poof] handleScannedCode — extracted code=\(code), calling joinWithCode")
        session.joinWithCode(code) { result in
            switch result {
            case let .success(peer):
                poofLog("[Poof] handleScannedCode — success peer=\(peer.name) id=\(peer.deviceId)")
                let kind = Self.deviceKind(for: peer.platform)
                onPair(PairedDevice(kind: kind, name: peer.name, peerId: peer.deviceId))
                dismiss()
            case let .failure(err):
                poofLog("[Poof] handleScannedCode — FAILED: \(err.localizedDescription)")
                pairFailure = err.localizedDescription
            }
        }
    }

    /// Accepte : "ABCDEF" · "poof://pair/ABCDEF" · "https://…/#pair=ABCDEF" · "…?pair=ABCDEF"
    static func extractPairCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "pair=") {
            let tail = trimmed[range.upperBound...]
            let code = tail.prefix { $0.isLetter || $0.isNumber }
            if !code.isEmpty {
                return String(code).uppercased()
            }
        }
        if trimmed.lowercased().hasPrefix("poof://pair/") {
            let code = trimmed.dropFirst("poof://pair/".count)
                .prefix { $0.isLetter || $0.isNumber }
            if !code.isEmpty {
                return String(code).uppercased()
            }
        }
        let stripped = trimmed.filter { $0.isLetter || $0.isNumber }
        return stripped.isEmpty ? nil : stripped.uppercased()
    }

    static func deviceKind(for platform: String) -> DeviceKind {
        switch platform.lowercased() {
        case "mac", "macos", "macbook": .macbook
        case "ios-pad", "ipad", "ipados": .ipad
        default: .iphone
        }
    }
}

// MARK: - Nearby peer model

struct NearbyPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: DeviceKind
    /// MC discovered peer sous-jacent — utilisé par `pairNearby` pour envoyer
    /// l'invite MC via `PoofNearbyPairing.shared.invite(...)`.
    let source: PoofNearbyPairing.DiscoveredPeer
}

// MARK: - Nearby discovery store (branché sur PoofNearbyPairing via MC)

@MainActor
final class NearbyPeerStore: ObservableObject {
    @Published private(set) var peers: [NearbyPeer] = []

    private let pairing = PoofNearbyPairing.shared
    private var cancellable: AnyCancellable?

    var myInviteURL: URL {
        URL(string: "https://poof.app/pair/\(String.randomPairingCode())")!
    }

    /// Démarre le browsing MC — l'advertising tourne déjà en permanence
    /// depuis `PoofSession.start()`. On observe la liste des `DiscoveredPeer`
    /// et on la re-project en `NearbyPeer` pour l'affichage.
    func start() {
        pairing.startBrowsing()
        cancellable = pairing.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovered in
                self?.peers = discovered.map { d in
                    NearbyPeer(id: d.id, name: d.name, kind: d.kind, source: d)
                }
            }
    }

    func stop() {
        pairing.stopBrowsing()
        cancellable?.cancel()
        cancellable = nil
    }

    /// Envoie une demande de pairing MC au peer sélectionné. Le device
    /// distant reçoit un sheet accept/deny (via `nearbyInvitationSheet`).
    func invite(_ peer: NearbyPeer) {
        pairing.invite(peer.source)
    }
}

private extension String {
    static func randomPairingCode() -> String {
        String(format: "%06d", Int.random(in: 0 ..< 1_000_000))
    }
}

// MARK: - QR Scanner (AVFoundation) — cross-platform iOS + macOS

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                QRScannerRepresentable(onScan: onScan)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 260, height: 260)
                    Spacer()
                    Text("Cadre le QR code de l'autre appareil")
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.bottom, 60)
                }
            }
            .navigationTitle("Scanner un QR")
            .poofInlineNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.white)
                }
            }
            .poofDarkNavBar()
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}

#if canImport(UIKit)
    private struct QRScannerRepresentable: UIViewControllerRepresentable {
        let onScan: (String) -> Void

        func makeUIViewController(context _: Context) -> QRScannerViewControllerIOS {
            let vc = QRScannerViewControllerIOS()
            vc.onScan = onScan
            return vc
        }

        func updateUIViewController(_: QRScannerViewControllerIOS, context _: Context) {}
    }

    final class QRScannerViewControllerIOS: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var didScan = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            requestAccessThenSetup()
        }

        private func requestAccessThenSetup() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.setupSession() }
            }
        }

        private func setupSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard !didScan,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = obj.stringValue else { return }
            didScan = true
            PoofHaptics.success()
            onScan?(code)
        }
    }
#elseif canImport(AppKit)
    private struct QRScannerRepresentable: NSViewControllerRepresentable {
        let onScan: (String) -> Void

        func makeNSViewController(context _: Context) -> QRScannerViewControllerMac {
            let vc = QRScannerViewControllerMac()
            vc.onScan = onScan
            return vc
        }

        func updateNSViewController(_: QRScannerViewControllerMac, context _: Context) {}
    }

    final class QRScannerViewControllerMac: NSViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didScan = false

        override func loadView() {
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 480))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.black.cgColor
            view = v
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            requestAccessThenSetup()
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            previewLayer?.frame = view.bounds
        }

        private func requestAccessThenSetup() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.setupSession() }
            }
        }

        private func setupSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(preview)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        override func viewWillDisappear() {
            super.viewWillDisappear()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard !didScan,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = obj.stringValue else { return }
            didScan = true
            PoofHaptics.success()
            onScan?(code)
        }
    }
#endif

// MARK: - Mon QR sheet

struct MyQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: PoofSession

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Have the other device scan this QR.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                if let code = session.pairCode {
                    if let img = Self.generateQR("poof://pair/\(code)") {
                        Image(poofImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                    }
                    Text(code)
                        .font(.system(.title2, design: .monospaced).bold())
                        .tracking(6)
                } else {
                    ProgressView()
                        .frame(width: 260, height: 260)
                    Text("Generating code…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .navigationTitle("My QR")
            .poofInlineNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if session.pairCode == nil {
                session.requestPairCode()
            }
        }
        .onDisappear {
            session.cancelPair()
        }
        .onChange(of: session.activePeerId) { _, newValue in
            if newValue != nil {
                dismiss()
            }
        }
    }

    static func generateQR(_ text: String) -> PoofImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return PoofImage.poofFromCGImage(cg)
    }
}

// MARK: - Invitation sheet (ShareLink)

struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                Text("Send an invitation")
                    .font(.title2.bold())

                Text(
                    "The other person clicks the link, downloads Poof or receives the file directly in their browser."
                )
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                ShareLink(
                    item: url,
                    subject: Text("Join me on Poof"),
                    message: Text("Open this link to receive my Poof transfer: \(url.absoluteString)")
                ) {
                    Label("Partager le lien", systemImage: "square.and.arrow.up")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Invitation")
            .poofInlineNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Code entry sheet

struct CodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code: String = ""
    @FocusState private var focused: Bool
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "number.square.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                Text("Enter the 6-character code")
                    .font(.title2.bold())

                Text("Ask the other person — it's displayed on their screen under « My QR ».")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                TextField("ABC 123", text: $code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                #if canImport(UIKit)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                #endif
                    .focused($focused)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15)))
                    .padding(.horizontal, 24)
                    .onChange(of: code) { _, new in
                        code = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    }

                Button {
                    onSubmit(code)
                } label: {
                    Text("Pair")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(code.count == 6 ? Color.blue : Color.gray.opacity(0.4)))
                }
                .disabled(code.count != 6)
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Code")
            .poofInlineNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
