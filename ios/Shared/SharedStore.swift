import Foundation

// Bridge between the Share Extension and the main app.
// Files land in the App Group container; a JSON queue lists them so the
// main app drains and re-injects them into PoofFileTransfer on next open
// (or immediately if it's already running, via the URL scheme handoff).

enum SharedStore {
    /// Must match the App Group ID configured on BOTH targets in Xcode
    /// (Signing & Capabilities → App Groups).
    static let appGroupID = "group.com.poofapp.shared"

    /// URL scheme the extension uses to wake the main app.
    /// Must match `CFBundleURLSchemes` in the main app Info.plist.
    static let urlScheme = "poof"

    struct PendingItem: Codable, Equatable {
        let id: String
        let filename: String
        let mime: String
        let addedAt: TimeInterval
        /// Path relative to the App Group container's "Inbox" folder.
        let relativePath: String
    }

    // MARK: - Container

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func inboxURL() -> URL? {
        guard let c = containerURL() else { return nil }
        let url = c.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func queueURL() -> URL? {
        containerURL()?.appendingPathComponent("pending.json")
    }

    // MARK: - Queue

    static func loadQueue() -> [PendingItem] {
        guard let url = queueURL(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingItem].self, from: data)) ?? []
    }

    static func saveQueue(_ items: [PendingItem]) {
        guard let url = queueURL() else { return }
        let data = (try? JSONEncoder().encode(items)) ?? Data()
        try? data.write(to: url, options: .atomic)
    }

    static func enqueue(_ item: PendingItem) {
        var q = loadQueue()
        q.append(item)
        saveQueue(q)
    }

    static func remove(_ id: String) {
        var q = loadQueue()
        if let idx = q.firstIndex(where: { $0.id == id }) {
            let victim = q.remove(at: idx)
            if let inbox = inboxURL() {
                let file = inbox.appendingPathComponent(victim.relativePath)
                try? FileManager.default.removeItem(at: file)
            }
        }
        saveQueue(q)
    }

    static func fileURL(for item: PendingItem) -> URL? {
        inboxURL()?.appendingPathComponent(item.relativePath)
    }
}
