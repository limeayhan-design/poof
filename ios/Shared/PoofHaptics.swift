import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// Signature haptique de Poof — un seul endroit décide "à quoi ça doit ressembler
// dans les doigts". Chaque pattern est nommé par l'INTENTION (sendStart,
// pairSuccess…) plutôt que par la classe UIKit sous-jacente, pour qu'on puisse
// affiner la texture d'un feedback sans toucher les callers.
//
// macOS : le trackpad Force Touch a un vocabulaire beaucoup plus pauvre que le
// Taptic Engine iPhone. On mappe tout sur .generic / .alignment / .levelChange
// via NSHapticFeedbackManager. Sur un Mac sans trackpad, ces appels sont no-op.

enum PoofHaptics {
    /// Toggle global. Respecté par TOUS les patterns ci-dessous. Persisté via
    /// UserDefaults + exposé dans Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "poof.haptics.enabled") as? Bool ?? true
    }

    // MARK: - Simple taps

    static func tap() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    static func soft() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    // MARK: - Selection

    static func select() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    static func impactMedium() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    // MARK: - Notifications (résultats)

    static func success() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    static func error() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    static func warning() {
        guard isEnabled else { return }
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    // MARK: - High-level intents (préférés par les callers)

    static func sendStart() {
        impactMedium()
    }

    static func sendSuccess() {
        success()
    }

    static func sendError() {
        error()
    }

    static func pairSuccess() {
        success()
    }

    static func receive() {
        soft()
    }
}
