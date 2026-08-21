import AVFoundation
import CoreImage
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Encoder Studio — pré-traite les vidéos avant envoi pour qu'elles arrivent
/// upload-ready aux specs exactes de chaque plateforme sociale.
///
/// Deux modes :
/// - **Passthrough** (`.masterPassthrough`) : `AVAssetExportPresetPassthrough`,
///   remuxe sans réencode, préserve codec + bitrate + resolution du master.
/// - **Plateforme sociale** : `AVMutableVideoComposition` avec `renderSize`
///   custom (1080×1920 pour Reels/TikTok/Shorts, 1080×1350 LinkedIn) +
///   `AVAssetExportPresetHighestQuality` → H.264 + AAC standard, upload
///   direct sans recompression par le serveur social.
///
/// Watermark : si `applyWatermark`, un `CATextLayer` est ajouté via
/// `AVVideoCompositionCoreAnimationTool` — gravé dans les pixels, indélébile.
enum PoofStudioEncoder {
    enum EncodeError: Error, LocalizedError {
        case sessionCreationFailed
        case exportFailed(String)
        case noVideoTrack

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed: "Could not create export session."
            case let .exportFailed(msg): "Encode failed: \(msg)"
            case .noVideoTrack: "Source has no video track."
            }
        }
    }

    static func encode(source: URL, config: StudioConfig) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent
            + "-\(config.platform.rawValue).mp4"
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)

        if config.platform.usesPassthrough {
            // Master → simple remux MP4, aucun réencode (le plus rapide).
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw EncodeError.sessionCreationFailed
            }
            session.outputURL = dest
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            try await session.export(to: dest, as: .mp4)
        } else {
            try await exportWithComposition(asset: asset, dest: dest, config: config)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0 else { throw EncodeError.exportFailed("Empty output file") }
        return dest
    }

    // MARK: - Plateforme sociale (renderSize custom + watermark optionnel)

    private static func exportWithComposition(
        asset: AVURLAsset,
        dest: URL,
        config: StudioConfig
    ) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw EncodeError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let frameDuration = try await track.load(.minFrameDuration)

        // Composition principale : garde audio + video du master.
        let composition = AVMutableComposition()
        if let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: track, at: .zero
            )
            videoTrack.preferredTransform = transform
        }
        if let audioSource = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try? audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioSource, at: .zero
            )
        }

        // Composition vidéo : renderSize plateforme + aspect fill (crop centré
        // si aspect source diffère). L'audio n'est pas touché.
        let renderSize = config.platform.renderSize
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration.isValid && frameDuration.value > 0
            ? frameDuration
            : CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        if let compVideoTrack = composition.tracks(withMediaType: .video).first {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
            layerInstruction.setTransform(
                fillTransform(source: naturalSize, target: renderSize, source_pref: transform),
                at: .zero
            )
            instruction.layerInstructions = [layerInstruction]
        }
        videoComposition.instructions = [instruction]

        // Watermark optionnel — CATextLayer overlay via CoreAnimation tool.
        if config.applyWatermark, !config.watermarkText.isEmpty {
            attachWatermark(
                text: config.watermarkText, to: videoComposition, size: renderSize
            )
        }

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw EncodeError.sessionCreationFailed
        }
        session.outputURL = dest
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        try await session.export(to: dest, as: .mp4)
    }

    // MARK: - Transform aspect fill

    /// Calcule le CGAffineTransform qui redimensionne + centre la source
    /// dans la renderSize cible (aspect fill = remplit entièrement, crop
    /// centré si nécessaire). Applique aussi le preferred transform source
    /// (orientation caméra).
    private static func fillTransform(
        source: CGSize,
        target: CGSize,
        source_pref: CGAffineTransform
    ) -> CGAffineTransform {
        // 1. Applique l'orientation naturelle de la source (portrait vs paysage).
        let orientedSize = source.applying(source_pref)
        let w = abs(orientedSize.width)
        let h = abs(orientedSize.height)
        // 2. Facteur d'échelle pour "fill" (max des ratios) — l'excédent est
        //    croppé par la renderSize.
        let scale = max(target.width / w, target.height / h)
        // 3. Centre : décale de (target - scaled)/2 pour centrer le contenu.
        let tx = (target.width - w * scale) / 2
        let ty = (target.height - h * scale) / 2
        return source_pref
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    // MARK: - Watermark

    private static func attachWatermark(
        text: String,
        to composition: AVMutableVideoComposition,
        size: CGSize
    ) {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let video = CALayer()
        video.frame = parent.frame
        parent.addSublayer(video)

        let watermark = CATextLayer()
        watermark.string = text
        watermark.font = "HelveticaNeue-Bold" as CFTypeRef
        watermark.fontSize = size.height * 0.03
        watermark.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.65)
        watermark.shadowOpacity = 0.5
        watermark.shadowRadius = 2
        watermark.alignmentMode = .right
        watermark.contentsScale = 3
        let margin: CGFloat = size.height * 0.04
        let boxHeight = size.height * 0.05
        watermark.frame = CGRect(
            x: 0,
            y: margin,
            width: size.width - margin,
            height: boxHeight
        )
        parent.addSublayer(watermark)

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: video, in: parent
        )
    }

    // MARK: - Batch

    /// Batch encode — encode chaque source séquentiellement avec la même
    /// config. Retourne la liste des URLs encodés (ordre préservé, sources
    /// en erreur skippées silencieusement).
    static func batchEncode(sources: [URL], config: StudioConfig) async -> [URL] {
        var results: [URL] = []
        for source in sources {
            do {
                let encoded = try await encode(source: source, config: config)
                results.append(encoded)
            } catch {
                continue
            }
        }
        return results
    }
}
