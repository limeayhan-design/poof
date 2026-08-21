import Foundation

#if canImport(UIKit)
    import UIKit

    public typealias PoofImage = UIImage
    public typealias PoofColor = UIColor
#elseif canImport(AppKit)
    import AppKit

    public typealias PoofImage = NSImage
    public typealias PoofColor = NSColor
#endif

/// Petit helper cross-platform pour ce qui doit exister sur iOS et macOS mais
/// n'a pas d'équivalent API-compatible entre UIKit et AppKit (clipboard,
/// device name, haptics stubs).
enum PoofPlatform {
    /// Nom de l'appareil courant (iPhone name sur iOS, ComputerName sur macOS).
    static var deviceName: String {
        #if canImport(UIKit)
            return UIDevice.current.name
        #elseif canImport(AppKit)
            return Host.current().localizedName ?? "Mac"
        #else
            return "Device"
        #endif
    }

    /// Modèle brut : "iPhone", "iPad", "Mac", etc.
    static var deviceModel: String {
        #if canImport(UIKit)
            return UIDevice.current.model
        #elseif canImport(AppKit)
            return "Mac"
        #else
            return "Device"
        #endif
    }

    /// Plateforme au format "iOS" / "iPadOS" / "macOS" pour l'annonce Bonjour.
    static var platform: String {
        #if canImport(UIKit)
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "iPadOS"
            case .mac: return "macOS"
            default: return "iOS"
            }
        #elseif canImport(AppKit)
            return "macOS"
        #else
            return "Unknown"
        #endif
    }

    /// SF Symbol représentant l'appareil courant — affiché à côté du nuage
    /// dans le header pour que l'utilisateur voie sur quel device il est.
    static var deviceSFSymbol: String {
        #if canImport(UIKit)
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "ipad"
            case .mac: return "laptopcomputer"
            default: return "iphone"
            }
        #elseif canImport(AppKit)
            return "laptopcomputer"
        #else
            return "desktopcomputer"
        #endif
    }

    /// Label court pour l'appareil courant ("iPhone" / "iPad" / "Mac").
    static var deviceShortLabel: String {
        #if canImport(UIKit)
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "iPad"
            case .mac: return "Mac"
            default: return "iPhone"
            }
        #elseif canImport(AppKit)
            return "Mac"
        #else
            return "Device"
        #endif
    }

    // MARK: - Clipboard

    static var clipboardString: String? {
        #if canImport(UIKit)
            return UIPasteboard.general.string
        #elseif canImport(AppKit)
            return NSPasteboard.general.string(forType: .string)
        #else
            return nil
        #endif
    }

    static func setClipboardString(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static var clipboardImage: PoofImage? {
        #if canImport(UIKit)
            return UIPasteboard.general.image
        #elseif canImport(AppKit)
            guard let data = NSPasteboard.general.data(forType: .tiff) else { return nil }
            return NSImage(data: data)
        #else
            return nil
        #endif
    }

    // MARK: - File picker (Mac uniquement)

    // Ouvre synchro un `NSOpenPanel` sur macOS. iOS n'a rien à faire ici : la
    // vue SwiftUI utilise `.fileImporter` natif qui fonctionne parfaitement.
    // Le `.fileImporter` sur Mac, en revanche, échoue à s'afficher quand il
    // est attaché à un panel dans un ZStack overlay — NSOpenPanel bypasse le
    // problème en présentant directement via l'app-level NSWindow.
    #if canImport(AppKit)
        @MainActor
        static func pickFiles(allowMultiple: Bool, completion: @escaping ([URL]) -> Void) {
            // Force l'app à passer active avant runModal — sinon la sheet
            // système NSOpenPanel peut être ignorée si l'app n'a pas le focus
            // (arrive après un tap sur un Button SwiftUI dans un overlay).
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = allowMultiple
            panel.title = "Choose file"
            panel.prompt = "Choose"
            panel.level = .modalPanel
            print("[Poof] NSOpenPanel about to runModal")
            let response = panel.runModal()
            print("[Poof] NSOpenPanel runModal returned \(response.rawValue)")
            if response == .OK {
                completion(panel.urls)
            } else {
                completion([])
            }
        }
    #endif
}

// MARK: - Debug logging

/// Remplace `print()` dans le codebase — no-op en release, évite la fuite de
/// tokens / peer IDs / URLs signaling dans les logs Console App production.
@inlinable
func poofLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
        let joined = items.map { "\($0)" }.joined(separator: separator)
        Swift.print(joined, terminator: terminator)
    #endif
}

// MARK: - Image → Data helpers

extension PoofImage {
    /// PNG cross-platform.
    var poofPNGData: Data? {
        #if canImport(UIKit)
            return pngData()
        #elseif canImport(AppKit)
            guard let tiff = tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        #else
            return nil
        #endif
    }

    /// JPEG cross-platform avec qualité paramétrable.
    func poofJPEGData(quality: CGFloat = 0.8) -> Data? {
        #if canImport(UIKit)
            return jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
            guard let tiff = tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
            return nil
        #endif
    }

    /// Encode l'image en JPEG base64, sous une taille max. Réduit la qualité
    /// itérativement (0.8 → 0.3) jusqu'à respecter `maxBytes`. Retourne nil
    /// si l'image est irréductible. Utilisé pour pousser l'avatar via
    /// socket.io sans exploser la 1 MB limit.
    func compressedJPEGBase64(maxBytes: Int) -> String? {
        for quality in stride(from: 0.8, through: 0.3, by: -0.15) {
            guard let data = poofJPEGData(quality: CGFloat(quality)) else { continue }
            if data.count <= maxBytes {
                return data.base64EncodedString()
            }
        }
        return nil
    }
}

// MARK: - SwiftUI Image bridge

import SwiftUI

extension SwiftUI.Image {
    /// Cross-platform init from `PoofImage` (`UIImage` on iOS, `NSImage` on macOS).
    init(poofImage: PoofImage) {
        #if canImport(UIKit)
            self.init(uiImage: poofImage)
        #elseif canImport(AppKit)
            self.init(nsImage: poofImage)
        #else
            self.init(systemName: "photo")
        #endif
    }
}
