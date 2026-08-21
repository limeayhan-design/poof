import UIKit
import UniformTypeIdentifiers

// Poof Share Extension.
// Consumes every attachment the host app shared (images, files, URLs, text),
// materialises them into the App Group inbox, appends metadata to the pending
// queue, then hands off to the main Poof app via URL scheme.
//
// The extension does NOT touch WebRTC or the signaling socket — extensions
// have a ~30s wall clock and heavy sandbox restrictions on background sockets.
// The main app picks up the queue on `.onOpenURL` and sends via the existing
// PoofFileTransfer pipeline.

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.075, blue: 0.145, alpha: 1)
        showSpinner()

        Task {
            await ingestAllAttachments()
            await handoffToApp()
            complete()
        }
    }

    // MARK: - UI

    private let spinner = UIActivityIndicatorView(style: .large)
    private let label = UILabel()

    private func showSpinner() {
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        label.text = "Handing off to Poof…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14)
        ])
    }

    // MARK: - Attachment ingestion

    private func ingestAllAttachments() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            for provider in item.attachments ?? [] {
                await ingest(provider)
            }
        }
    }

    private func ingest(_ provider: NSItemProvider) async {
        let candidates: [UTType] = [.fileURL, .image, .movie, .pdf, .url, .plainText, .data]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if await load(provider, type: type) {
                return
            }
        }
    }

    private func load(_ provider: NSItemProvider, type: UTType) async -> Bool {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { data, _ in
                let ok = self.materialise(data, hint: type)
                cont.resume(returning: ok)
            }
        }
    }

    // MARK: - Materialisation

    private func materialise(_ raw: NSSecureCoding?, hint: UTType) -> Bool {
        guard let inbox = SharedStore.inboxURL() else { return false }
        let id = UUID().uuidString

        switch raw {
        case let url as URL where url.isFileURL:
            let dst = inbox.appendingPathComponent("\(id)_\(url.lastPathComponent)")
            do {
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: url, to: dst)
            } catch { return false }
            SharedStore.enqueue(.init(
                id: id,
                filename: url.lastPathComponent,
                mime: mime(for: url.pathExtension),
                addedAt: Date().timeIntervalSince1970,
                relativePath: dst.lastPathComponent
            ))
            return true

        case let url as URL:
            return writeText(url.absoluteString, id: id, filename: "link.txt", inbox: inbox)

        case let text as String:
            return writeText(text, id: id, filename: "text.txt", inbox: inbox)

        case let img as UIImage:
            guard let data = img.pngData() else { return false }
            return writeBlob(data, id: id, filename: "image.png", mime: "image/png", inbox: inbox)

        case let data as Data:
            let ext = hint.preferredFilenameExtension ?? "bin"
            return writeBlob(
                data,
                id: id,
                filename: "share.\(ext)",
                mime: hint.preferredMIMEType ?? "application/octet-stream",
                inbox: inbox
            )

        default:
            return false
        }
    }

    private func writeText(_ text: String, id: String, filename: String, inbox: URL) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return writeBlob(data, id: id, filename: filename, mime: "text/plain", inbox: inbox)
    }

    private func writeBlob(_ data: Data, id: String, filename: String, mime: String, inbox: URL) -> Bool {
        let dst = inbox.appendingPathComponent("\(id)_\(filename)")
        do { try data.write(to: dst, options: .atomic) } catch { return false }
        SharedStore.enqueue(.init(
            id: id,
            filename: filename,
            mime: mime,
            addedAt: Date().timeIntervalSince1970,
            relativePath: dst.lastPathComponent
        ))
        return true
    }

    private func mime(for ext: String) -> String {
        UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    // MARK: - Handoff

    private func handoffToApp() async {
        guard let url = URL(string: "\(SharedStore.urlScheme)://share?drain=1") else { return }
        // openURL on UIApplication is unavailable in extensions — walk the
        // responder chain to find one that responds.
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                _ = await app.open(url, options: [:])
                return
            }
            responder = r.next
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
