import SwiftUI
import AVKit
import Photos
import QuickLook

// Preview + save/share the last file received over Poof.

struct ReceivedFileSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var showShare = false
    @State private var toastText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                VStack(spacing: 18) {
                    preview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    metadataRow
                    actionRow
                }
                .padding(.bottom, 16)

                if let toast = toastText {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.8)))
                            .padding(.bottom, 100)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(PoofTheme.accent)
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18))
        case .video:
            VideoPlayer(player: AVPlayer(url: url))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        case .other:
            VStack(spacing: 14) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 62, weight: .light))
                    .foregroundColor(PoofTheme.accent)
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(radius: 22)
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .foregroundColor(PoofTheme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .lineLimit(1)
                Text(sizeText)
                    .font(.system(size: 11))
                    .foregroundColor(PoofTheme.textTertiary)
            }
            Spacer()
        }
        .padding(12)
        .glassCard()
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            if kind.canSaveToPhotos {
                actionButton(icon: "square.and.arrow.down", label: "Photos", tint: PoofTheme.accent) {
                    saveToPhotos()
                }
            }
            actionButton(icon: "square.and.arrow.up", label: "Share", tint: .white.opacity(0.15)) {
                showShare = true
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photos save

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { flash("Photos access denied") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let type: PHAssetResourceType = kind.isVideo ? .video : .photo
                req.addResource(with: type, fileURL: url, options: nil)
            }) { ok, _ in
                DispatchQueue.main.async {
                    flash(ok ? "Saved to Photos" : "Save failed")
                }
            }
        }
    }

    private func flash(_ text: String) {
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toastText == text { toastText = nil }
        }
    }

    // MARK: - Kind detection

    private enum Kind {
        case image(UIImage)
        case video
        case other

        var icon: String {
            switch self {
            case .image: return "photo.fill"
            case .video: return "film.fill"
            case .other: return "doc.fill"
            }
        }
        var canSaveToPhotos: Bool {
            if case .other = self { return false }
            return true
        }
        var isVideo: Bool { if case .video = self { return true }; return false }
    }

    private var kind: Kind {
        let ext = url.pathExtension.lowercased()
        let videos: Set<String> = ["mov", "mp4", "m4v", "hevc"]
        if videos.contains(ext) { return .video }
        if let img = UIImage(contentsOfFile: url.path) { return .image(img) }
        return .other
    }

    private var sizeText: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
