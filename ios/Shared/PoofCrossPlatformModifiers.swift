import SwiftUI

// Petits shims SwiftUI cross-platform : les modificateurs `navigationBarTitleDisplayMode`,
// `listStyle(.insetGrouped)`, `toolbarBackground(_:for: .navigationBar)`,
// `keyboardType(...)` n'existent QUE sur iOS. Sur macOS on retombe sur le style par
// défaut (ou équivalent le plus proche) pour que le même code source compile.

extension View {
    @ViewBuilder
    func poofInlineNav() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    @ViewBuilder
    func poofInsetListStyle() -> some View {
        #if os(iOS)
            listStyle(.insetGrouped)
        #else
            listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func poofDarkNavBar() -> some View {
        #if os(iOS)
            toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        #else
            self
        #endif
    }

    @ViewBuilder
    func poofNumberKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
        #else
            self
        #endif
    }
}

/// Cross-platform init pour PoofImage depuis CGImage.
extension PoofImage {
    static func poofFromCGImage(_ cg: CGImage) -> PoofImage {
        #if canImport(UIKit)
            return UIImage(cgImage: cg)
        #else
            // macOS : `NSImage(cgImage:size:)` avec une size en pixels bruts
            // (ex. QR code scaled ×10) crée une image que SwiftUI n'affiche
            // pas correctement — la vue restait vide. Passer explicitement
            // par un `NSBitmapImageRep` garantit une représentation lisible
            // par SwiftUI + AppKit.
            let rep = NSBitmapImageRep(cgImage: cg)
            let img = NSImage(size: rep.size)
            img.addRepresentation(rep)
            return img
        #endif
    }
}
