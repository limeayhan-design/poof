import SwiftUI

// Bottom sheet — Figma Tvvo6kXMeIpDj7VGG0KsDW / iPhone 19.
// Three OptionCardRow atoms stacked, spacing: 0 with an explicit vertical gap
// between rows. The sheet's background gradient is defined by the parent
// (`presentationBackground` in PoofRootView).

struct PoofSendOptionsSheet: View {
    let onPickPhotos: () -> Void
    let onPickFiles: () -> Void
    let onPushClipboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OptionCardRow(
                icon: "photo.on.rectangle.angled",
                iconSize: 26,
                title: "Photos & Videos",
                subtitle: "Pick images or clips from your library and send them instantly.",
                action: onPickPhotos
            )
            .padding(.bottom, 12)
            .appleEntry(delay: 0.05)

            OptionCardRow(
                icon: "doc.fill",
                iconSize: 26,
                title: "Files",
                subtitle: "Browse documents, PDFs, or any file from your device.",
                action: onPickFiles
            )
            .padding(.bottom, 12)
            .appleEntry(delay: 0.12)

            OptionCardRow(
                icon: "doc.on.clipboard.fill",
                iconSize: 24,
                title: "Clipboard",
                subtitle: "Instantly send whatever you last copied — text, image, or link.",
                action: onPushClipboard
            )
            .appleEntry(delay: 0.19)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PoofTokens.screenHPadding)
        .padding(.top, 24)
    }
}
