import SwiftUI

// Design tokens — source of truth for the Figma Tvvo6kXMeIpDj7VGG0KsDW spec.
// Every card size, colour, radius, and font weight in Home / Send / SendOptions
// derives from this enum so redesigns stay a single-file change.

enum PoofTokens {
    // MARK: - Colours (hex from Figma)

    /// #05050D — near-black canvas background.
    static let canvas = Color(red: 5.0 / 255, green: 5.0 / 255, blue: 13.0 / 255)

    /// #0165FB — top stop of every hero card gradient.
    static let cardBlueTop = Color(red: 1.0 / 255, green: 101.0 / 255, blue: 251.0 / 255)

    /// #0050D8 — bottom stop of every hero card gradient.
    static let cardBlueBottom = Color(red: 0.0, green: 80.0 / 255, blue: 216.0 / 255)

    /// Vertical gradient used on every MainCard.
    static let cardGradient = LinearGradient(
        colors: [cardBlueTop, cardBlueBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// #2C2E3A — dark blue-grey tile used for device bubbles / neutral icons.
    static let darkTile = Color(red: 44.0 / 255, green: 46.0 / 255, blue: 58.0 / 255)

    /// Container fill for the "My devices" / "Detected nearby" sections.
    static let sectionFill = Color(red: 22.0 / 255, green: 22.0 / 255, blue: 30.0 / 255)

    /// Text.
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)

    /// Subtle white hairline that separates hero body from footer.
    static let hairline = Color.white.opacity(0.22)

    // MARK: - Typography — SF Pro Rounded ladder

    // Rounded design across the board = Poof brand voice (softer, playful,
    // matches the cloud wordmark). Reserve non-rounded for body copy only if
    // a specific screen ever demands editorial density.

    static let displayLarge = Font.system(size: 68, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 48, weight: .bold, design: .rounded)
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 20, weight: .bold, design: .rounded)
    static let cardBody = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let sectionLabel = Font.system(size: 22, weight: .bold, design: .rounded)
    static let body = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let bodyRegular = Font.system(size: 15, weight: .regular, design: .rounded)
    static let callout = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let footnote = Font.system(size: 13, weight: .medium, design: .rounded)
    static let bubbleLabel = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let finePrint = Font.system(size: 12, weight: .regular, design: .rounded)

    // MARK: - Radii

    /// 32pt — every hero / large card in the Figma.
    static let radiusCard: CGFloat = 32

    /// 16pt — icon tiles, small badges.
    static let radiusIcon: CGFloat = 16

    // MARK: - Spacing / paddings

    /// Horizontal padding around every card row.
    static let screenHPadding: CGFloat = 16

    /// Vertical spacing between the two Home cards.
    static let cardVSpacing: CGFloat = 16

    /// Horizontal padding inside a card (title / footer inset).
    static let cardHInset: CGFloat = 22

    // MARK: - Fixed heights (Figma spec)

    /// Send hero and any "compact" hero — same visual mass on top of screen.
    static let heroCardHeight: CGFloat = 340

    /// Home top card — taller because it carries the wordmark + subscriptions footer.
    static let homeHeroHeight: CGFloat = 500

    /// Home bottom card — Explore block with the 4-square glyph.
    static let exploreHeight: CGFloat = 280

    /// Height of each device bubble container ("My devices").
    static let devicesRowHeight: CGFloat = 156

    /// Height of the "Detected nearby" empty container.
    static let nearbyHeight: CGFloat = 175
}
