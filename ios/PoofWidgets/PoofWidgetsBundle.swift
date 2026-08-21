import SwiftUI
import WidgetKit

// Bundle entry point for the PoofWidgets extension. Only ships the Live
// Activity widget for now — no static / interactive widgets planned.

@main
struct PoofWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PoofTransferLiveActivity()
        // Deployment target = iOS 27, on peut inclure inconditionnellement.
        // Un `if #available` dans un WidgetBundleBuilder a montré des cas
        // où iOS 18 ne détecte pas le Control Widget dans la Command Center
        // list — le déclarer direct évite ça.
        PoofPasteControl()
    }
}
