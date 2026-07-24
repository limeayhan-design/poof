import ReplayKit
import UIKit
import ImageIO
import CoreImage
import CoreServices

// Broadcast Upload Extension entry point.
// Receives CMSampleBuffer @ up to 60 FPS. We throttle to ~10 FPS, encode as JPEG,
// and atomically write to a shared App Group container file.
// The main app watches that file (Darwin notification + poll fallback) and
// forwards the JPEG bytes over the WebRTC bulk channel to the peer.
//
// Extensions run in a memory-limited (~50 MB) process. We deliberately do NOT
// hold the WebRTC connection here — the main app handles transport.

private let appGroupId = "group.com.atlas.link.poof"
private let frameFilename = "screen-mirror.jpg"
private let notificationName = "com.atlas.link.poof.screenMirror.frame"
private let targetFPS: Double = 10
private let jpegQuality: CGFloat = 0.4
private let maxDimension: CGFloat = 720

final class SampleHandler: RPBroadcastSampleHandler {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastFrameAt: CFTimeInterval = 0
    private lazy var containerURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        writeStatus(started: true)
    }

    override func broadcastPaused() { }
    override func broadcastResumed() { }

    override func broadcastFinished() {
        writeStatus(started: false)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CACurrentMediaTime()
        let interval = 1.0 / targetFPS
        guard now - lastFrameAt >= interval else { return }
        lastFrameAt = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let containerURL else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = downscale(ciImage)
        guard let jpeg = encodeJPEG(scaled) else { return }

        let dest = containerURL.appendingPathComponent(frameFilename)
        let tmp = containerURL.appendingPathComponent(frameFilename + ".tmp")
        do {
            try jpeg.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(dest, withItemAt: tmp)
            postDarwinNotification()
        } catch {
            // Extension memory pressure or disk hiccup — drop the frame silently.
        }
    }

    // MARK: - Helpers

    private func downscale(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func encodeJPEG(_ image: CIImage) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let options: [CIImageRepresentationOption: Any] = [
            .init(rawValue: kCGImageDestinationLossyCompressionQuality as String): jpegQuality
        ]
        return ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
    }

    private func writeStatus(started: Bool) {
        guard let containerURL else { return }
        let statusURL = containerURL.appendingPathComponent("screen-mirror.status")
        let payload = started ? "1" : "0"
        try? payload.write(to: statusURL, atomically: true, encoding: .utf8)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: "com.atlas.link.poof.screenMirror.status" as CFString),
            nil, nil, true
        )
    }

    private func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: notificationName as CFString),
            nil, nil, true
        )
    }
}
