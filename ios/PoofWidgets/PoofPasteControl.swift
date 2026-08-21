#if os(iOS)
    import AppIntents
    import SwiftUI
    import UIKit
    import WidgetKit

    // ⚠️ Copies locales de `PastePoofClipboardIntent` + shared store —
    // nécessaires car le widget target n'inclut pas le folder Shared/
    // dans ses fileSystemSynchronizedGroups (WebRTC/SocketIO deps y sont).
    // Toute modif du contract doit être répliquée dans les 2 fichiers.
    //
    // Same App Group + same keys que Shared/PoofAppIntents.swift → single
    // source of truth cross-target.

    enum PoofWidgetSharedStore {
        static let appGroupId = "group.com.poofapp.shared"
        static let textKey = "poof.lastClipboardText"
        static let senderKey = "poof.lastClipboardSender"

        static var defaults: UserDefaults {
            UserDefaults(suiteName: appGroupId) ?? .standard
        }

        static var latestText: String? {
            let t = defaults.string(forKey: textKey)
            return (t?.isEmpty == false) ? t : nil
        }
    }

    struct PastePoofClipboardIntent: AppIntent {
        static var title: LocalizedStringResource = "Paste from Poof"
        static var description = IntentDescription(
            "Pastes the last text received from a linked Poof device."
        )
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult {
            guard let text = PoofWidgetSharedStore.latestText else {
                return .result()
            }
            await MainActor.run {
                UIPasteboard.general.string = text
                UIPasteboard.general.setValue(text, forPasteboardType: "public.utf8-plain-text")
            }
            return .result()
        }
    }

    struct PoofPasteControl: ControlWidget {
        var body: some ControlWidgetConfiguration {
            StaticControlConfiguration(kind: "com.Poof.App.PasteControl") {
                ControlWidgetButton(action: PastePoofClipboardIntent()) {
                    Label("Paste Poof", systemImage: "doc.on.clipboard.fill")
                }
            }
            .displayName("Paste Poof")
            .description("Paste the last clipboard received from a device linked to Poof.")
        }
    }
#endif
