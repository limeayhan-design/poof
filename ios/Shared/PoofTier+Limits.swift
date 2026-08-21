import Foundation

// Enforced constraints per tier. Enforced client-side in PairingSheet
// (device count) and PoofHomeView.handleFileSelection (file size).

extension PoofTier {
    /// Maximum number of paired devices. `nil` means unlimited.
    /// Aligned with paywall promise: Standard = 1 device, Premium = ∞.
    var maxPairedDevices: Int? {
        switch self {
        case .free: 1
        case .premium: nil
        case .family: nil
        case .devium: nil
        case .business: nil
        }
    }

    /// Maximum size of a single file, in bytes. `nil` means unlimited.
    /// Aligned with paywall promise: unlimited size on every tier (Poof's
    /// differentiator vs WeTransfer — we limit ubiquity, not raw size).
    var maxFileSize: UInt64? {
        switch self {
        case .free: nil
        case .premium: nil
        case .family: nil
        case .devium: nil
        case .business: nil
        }
    }

    /// Human-readable label for the file size limit.
    var maxFileSizeLabel: String {
        guard let bytes = maxFileSize else { return "Unlimited size" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Human-readable label for the pairing limit.
    var pairingLimitLabel: String {
        guard let n = maxPairedDevices else { return "Unlimited devices" }
        return "\(n) device\(n == 1 ? "" : "s")"
    }

    func canPairAnother(current: Int) -> Bool {
        guard let max = maxPairedDevices else { return true }
        return current < max
    }

    func canSendFile(size: UInt64) -> Bool {
        guard let max = maxFileSize else { return true }
        return size <= max
    }

    // MARK: - Feature capability flags (Premium unlocks all)

    // Aligned with paywall promises — every "Premium feature" listed must
    // be gated here so that Free users see a paywall trigger and Premium
    // users get real access.

    var isPremium: Bool {
        switch self {
        case .free: false
        case .premium, .family, .devium, .business: true
        }
    }

    /// Browse your other devices' files remotely.
    var canUseRemoteFiles: Bool {
        isPremium
    }

    /// Sync clipboard (text + files) across all devices.
    var canUseUniversalClipboard: Bool {
        isPremium
    }

    /// Show delivered / seen receipts on sent files.
    var canUseReadReceipts: Bool {
        isPremium
    }

    /// Drag & drop whole folders in one shot (vs single files).
    var canDropFolders: Bool {
        isPremium
    }

    /// Maximum age of history entries, in hours. `nil` means unlimited.
    /// Free = 24h auto-purge, Premium = full history.
    var maxHistoryAgeHours: Int? {
        isPremium ? nil : 24
    }
}
