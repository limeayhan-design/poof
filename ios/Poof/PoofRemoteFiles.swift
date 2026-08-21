import Foundation
import UniformTypeIdentifiers

// Remote-file browser over the control channel.
// Peer exposes its Documents/ directory (sandboxed on iOS, ~/Documents on Mac desktop).
//
// Wire:
//   → remoteListRequest  { path }
//   ← remoteListResponse { path, entries: [{name,isDir,size}] }
//   → remoteGetRequest   { path }   ← peer then streams as fileMeta + bulk frames

nonisolated struct RemoteEntry: Identifiable, Equatable {
    let name: String
    let isDir: Bool
    let size: UInt64
    var id: String {
        (isDir ? "d:" : "f:") + name
    }
}

final class PoofRemoteFiles {
    /// Handler for the peer's replies. Called on `queue` thread.
    var onListReceived: ((_ requestId: String, _ path: String, _ entries: [RemoteEntry]) -> Void)?

    private weak var manager: PoofWebRTCManager?
    private let queue = DispatchQueue(label: "poof.remote-files", qos: .userInitiated)

    init(manager: PoofWebRTCManager) {
        self.manager = manager
    }

    // MARK: - Requester side (this device browsing peer)

    @discardableResult
    func requestList(path: String) -> String {
        let id = UUID().uuidString
        manager?.sendEnvelope(PoofEnvelope(
            type: .remoteListRequest,
            id: id,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["path": path]
        ))
        return id
    }

    func requestGet(path: String) {
        manager?.sendEnvelope(PoofEnvelope(
            type: .remoteGetRequest,
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["path": path]
        ))
    }

    // MARK: - Responder side (peer browses us)

    func handle(_ env: PoofEnvelope, fileTransfer: PoofFileTransfer?) {
        switch env.type {
        case .remoteListRequest:
            respondList(env)
        case .remoteListResponse:
            handleListResponse(env)
        case .remoteGetRequest:
            respondGet(env, fileTransfer: fileTransfer)
        default: break
        }
    }

    private var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private func resolvedURL(for path: String) -> URL? {
        let cleaned = path
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = cleaned.isEmpty ? documentsRoot : documentsRoot.appendingPathComponent(cleaned)
        // Prevent escape outside sandbox.
        guard target.path.hasPrefix(documentsRoot.path) else { return nil }
        return target
    }

    private func respondList(_ env: PoofEnvelope) {
        let path = (env.payload["path"] as? String) ?? ""
        guard let url = resolvedURL(for: path) else { replyEmpty(env.id, path)
            return
        }
        var entries: [[String: Any]] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ) {
            for u in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                entries.append([
                    "name": u.lastPathComponent,
                    "isDir": vals?.isDirectory ?? false,
                    "size": vals?.fileSize ?? 0
                ])
            }
        }
        manager?.sendEnvelope(PoofEnvelope(
            type: .remoteListResponse,
            id: env.id,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["path": path, "entries": entries]
        ))
    }

    private func replyEmpty(_ id: String, _ path: String) {
        manager?.sendEnvelope(PoofEnvelope(
            type: .remoteListResponse,
            id: id,
            ts: Date().timeIntervalSince1970,
            force: false,
            payload: ["path": path, "entries": []]
        ))
    }

    private func handleListResponse(_ env: PoofEnvelope) {
        let path = (env.payload["path"] as? String) ?? ""
        let raw = (env.payload["entries"] as? [[String: Any]]) ?? []
        let entries: [RemoteEntry] = raw.compactMap {
            guard let name = $0["name"] as? String else { return nil }
            let isDir = ($0["isDir"] as? Bool) ?? false
            let size = ($0["size"] as? NSNumber)?.uint64Value ?? 0
            return RemoteEntry(name: name, isDir: isDir, size: size)
        }
        onListReceived?(env.id, path, entries)
    }

    private func respondGet(_ env: PoofEnvelope, fileTransfer: PoofFileTransfer?) {
        let path = (env.payload["path"] as? String) ?? ""
        guard let url = resolvedURL(for: path),
              FileManager.default.fileExists(atPath: url.path),
              let fileTransfer else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        Task { try? await fileTransfer.send(fileAt: url, mime: mime) }
    }
}
