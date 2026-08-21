import Foundation

/// Fallback fiable pour les transferts de fichier — bypass WebRTC en passant
/// par le serveur Render (upload HTTPS + notif socket.io au receiver +
/// download HTTPS). Plus lent que WebRTC direct mais 100% fiable : pas de
/// buffer SCTP, pas de handshake, pas de race meta/chunks.
enum PoofRelayClient {
    private static var baseURL: URL {
        PoofSession.signalingURL
    }

    struct UploadInput {
        let fileURL: URL
        let mime: String
        let targetDeviceId: String
        let senderDeviceId: String
        let transferId: UUID
        let secureConfig: SecureConfig?
        let trackConfig: TrackConfig?
        let compressed: Bool
        let overrideName: String?
    }

    /// POST /relay/upload — envoie le fichier binaire brut au serveur.
    /// Retourne le fileId si succès. Le serveur push automatiquement un
    /// event socket.io `relay-file-ready` au targetDeviceId.
    /// `onProgress` reçoit les bytes envoyés / total pour driver la Live
    /// Activity (Dynamic Island) en temps réel — sinon la progression
    /// reste à 0% jusqu'au succès final.
    static func upload(
        _ input: UploadInput,
        onProgress: ((UInt64, UInt64) -> Void)? = nil
    ) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("relay/upload"))
        req.httpMethod = "POST"
        req.setValue(input.mime, forHTTPHeaderField: "Content-Type")
        req.setValue(input.overrideName ?? input.fileURL.lastPathComponent, forHTTPHeaderField: "X-File-Name")
        req.setValue(input.mime, forHTTPHeaderField: "X-Mime-Type")
        req.setValue(input.targetDeviceId, forHTTPHeaderField: "X-Target-Device-Id")
        req.setValue(input.senderDeviceId, forHTTPHeaderField: "X-Sender-Device-Id")
        req.setValue(input.transferId.uuidString, forHTTPHeaderField: "X-Transfer-Id")
        req.setValue(input.compressed ? "true" : "false", forHTTPHeaderField: "X-Compressed")
        if let secure = input.secureConfig,
           let data = try? JSONEncoder().encode(secure),
           let json = String(data: data, encoding: .utf8)
        {
            req.setValue(json, forHTTPHeaderField: "X-Secure-Config")
        }
        if let track = input.trackConfig,
           let data = try? JSONEncoder().encode(track),
           let json = String(data: data, encoding: .utf8)
        {
            req.setValue(json, forHTTPHeaderField: "X-Track-Config")
        }
        let delegate = ProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: req, fromFile: input.fileURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RelayError.upload("HTTP \(status)")
        }
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let fileId = dict?["fileId"] as? String else {
            throw RelayError.upload("no fileId in response")
        }
        return fileId
    }

    /// URLSessionTaskDelegate qui relaie `didSendBodyData` à une closure
    /// simple. Utilisé pour driver la Live Activity Dynamic Island pendant
    /// l'upload HTTPS (sinon `URLSession.upload` async ne remonte que le
    /// résultat final, pas la progression intermédiaire).
    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let onProgress: ((UInt64, UInt64) -> Void)?
        init(onProgress: ((UInt64, UInt64) -> Void)?) {
            self.onProgress = onProgress
        }

        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            didSendBodyData _: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress?(UInt64(totalBytesSent), UInt64(totalBytesExpectedToSend))
        }
    }

    /// GET /relay/{fileId} — télécharge le fichier binaire. Le fichier est
    /// supprimé côté serveur après lecture (one-shot). Retourne l'URL locale
    /// du fichier téléchargé + les headers meta.
    static func download(fileId: String) async throws -> (localURL: URL, headers: [AnyHashable: Any]) {
        let url = baseURL.appendingPathComponent("relay/\(fileId)")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RelayError.download("HTTP \(status)")
        }
        // Copie dans un fichier permanent (URLSession supprime le temp au retour)
        let name = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-File-Name") ?? "file"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PoofRelay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return (dest, (response as? HTTPURLResponse)?.allHeaderFields ?? [:])
    }

    enum RelayError: Error, LocalizedError {
        case upload(String)
        case download(String)
        case clipboard(String)
        var errorDescription: String? {
            switch self {
            case let .upload(m): "Upload: \(m)"
            case let .download(m): "Download: \(m)"
            case let .clipboard(m): "Clipboard: \(m)"
            }
        }
    }

    /// POST /relay/clipboard — envoie un texte à un device même si son app
    /// n'est pas ouverte. Le serveur queue le texte + push socket.io (si
    /// online) + push APNS avec bouton d'action « 📋 Coller » (si iOS token
    /// enregistré). Le receiver colle sans devoir ouvrir Poof.
    static func pushClipboard(
        text: String,
        targetDeviceId: String,
        senderName: String
    ) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("relay/clipboard"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "targetDeviceId": targetDeviceId,
            "senderDeviceId": PoofDeviceIdentity.deviceId,
            "senderName": senderName,
            "text": text
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw RelayError.clipboard(msg)
        }
    }
}
