import SwiftUI

extension Color {
    static let poofBackground = Color(hex: "#000000")
    static let poofCardBlue = Color(hex: "#2B6FE6")
    static let poofCardBlueDark = Color(hex: "#1A4FCC")
    static let poofExploreTop = Color(hex: "#1E3A8A")
    static let poofExploreBottom = Color(hex: "#1E2F6E")
    static let poofIconBlue = Color(hex: "#2563EB")
    static let poofTabBar = Color(hex: "#111111")
    static let poofTabActive = Color.white
    static let poofTabInactive = Color(white: 0.5)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
