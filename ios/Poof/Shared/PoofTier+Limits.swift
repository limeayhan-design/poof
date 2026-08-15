import Foundation

// Enforced constraints per tier. Enforced client-side in PairingSheet
// (device count) and PoofHomeView.handleFileSelection (file size).

extension PoofTier {
    /// Maximum number of paired devices. `nil` means unlimited.
    var maxPairedDevices: Int? {
        switch self {
        case .free:     return 2
        case .premium:  return nil
        case .family:   return nil
        case .devium:   return nil
        case .business: return nil
        }
    }

    /// Maximum size of a single file, in bytes. `nil` means unlimited.
    var maxFileSize: UInt64? {
        switch self {
        case .free:     return 2 * 1024 * 1024 * 1024   // 2 GB
        case .premium:  return nil
        case .family:   return nil
        case .devium:   return nil
        case .business: return nil
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
}
