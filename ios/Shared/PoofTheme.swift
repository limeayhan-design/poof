import SwiftUI

// Design tokens — aligned with Figma file Tvvo6kXMeIpDj7VGG0KsDW.
// Palette Apple-tier: pure black canvas, deep blue gradients, cyan glow accents.
// Legacy tokens (bgBase/bgTop/bgBottom, glassFill, radiusLg/Md/Sm) kept so the
// existing sheets (PairingSheet, PricingSheet, HistorySheet…) still compile.

enum PoofTheme {
    // MARK: - Figma palette (source of truth going forward)

    /// #05050D — near-black canvas from the Figma spec.
    static let canvas = PoofTokens.canvas

    /// #0165FB — top stop of every hero card gradient.
    static let blueStart = PoofTokens.cardBlueTop

    /// #0050D8 — bottom stop of every hero card gradient.
    static let blueEnd = PoofTokens.cardBlueBottom

    /// Cyan glow kept for legacy hero shadows / halos.
    static let cyanGlow = Color(red: 0.0, green: 0.8, blue: 1.0) // #00CCFF

    /// Vertical top→bottom gradient matching the Figma spec.
    static let heroGradient = PoofTokens.cardGradient

    /// The subtle white hairline used on every big card in the design (0.1pt in Figma).
    static let cardHairline = Color.white.opacity(0.10)

    /// Ring color for a peer bubble in "last used / just sent to" state.
    static let ringGreen = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759

    /// Ring color for a peer bubble in "currently selected as target" state.
    static let ringBlue = blueStart

    // MARK: - Radii

    /// Corner radius on hero + big cards in the Figma (32pt).
    static let radiusCard: CGFloat = PoofTokens.radiusCard

    /// Corner radius on icon tiles / small badges (16pt in the Figma spec).
    static let radiusOption: CGFloat = PoofTokens.radiusIcon

    // MARK: - Legacy tokens (do not remove — used by existing sheets)

    static let bgBase = Color.black
    static let bgTop = Color(red: 0.043, green: 0.043, blue: 0.078)
    static let bgBottom = Color(red: 0.031, green: 0.031, blue: 0.055)

    static let accent = blueStart
    static let accent2 = blueEnd
    static let green = ringGreen
    static let danger = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let dropStroke = cyanGlow

    static let textPrimary = Color.white.opacity(0.98)
    static let textSecondary = Color.white.opacity(0.78)
    static let textTertiary = Color.white.opacity(0.62)

    static let glassFill = Color.white.opacity(0.06)
    static let glassFillHi = Color.white.opacity(0.10)
    static let glassStroke = Color.white.opacity(0.14)

    static let radiusLg: CGFloat = 22
    static let radiusMd: CGFloat = 16
    static let radiusSm: CGFloat = 12
}

// MARK: - Background

/// Plain black canvas — the Figma design uses pure black, no gradient wash.
/// Kept as a view so callers stay declarative.
struct PoofBackground: View {
    var body: some View {
        PoofTheme.canvas.ignoresSafeArea()
    }
}

// MARK: - Glass card modifier (legacy, still used by older sheets)

struct GlassCard: ViewModifier {
    var radius: CGFloat = PoofTheme.radiusMd
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PoofTheme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [PoofTheme.glassStroke, .white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = PoofTheme.radiusMd) -> some View {
        modifier(GlassCard(radius: radius))
    }

    /// Hairline overlay matching the Figma "0.1pt white border" on hero/big cards.
    func poofCardHairline(radius: CGFloat = PoofTheme.radiusCard) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(PoofTheme.cardHairline, lineWidth: 0.5)
        )
    }

    /// Apple-tier layered card shadow — three stops matching Wallet / Health cards.
    /// `tint` colours the ambient glow so blue cards feel emissive.
    func appleCardDepth(tint: Color = .black, intensity: CGFloat = 1) -> some View {
        shadow(color: .black.opacity(0.10 * intensity), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.22 * intensity), radius: 10, x: 0, y: 6)
            .shadow(color: tint.opacity(0.28 * intensity), radius: 36, x: 0, y: 18)
    }

    /// Inner top-rim highlight — mimics the glass sheen Apple puts on tinted cards.
    func appleRimHighlight(
        radius: CGFloat = PoofTheme.radiusCard,
        top: Double = 0.32,
        mid: Double = 0.06
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(top),
                            Color.white.opacity(mid),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.9
                )
                .allowsHitTesting(false)
        )
    }
}

/// Radial glow used behind hero glyphs (Fitness rings, Music Now Playing).
struct AppleRadialGlow: View {
    let color: Color
    var intensity: Double = 0.55
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(intensity), color.opacity(0)],
                    center: .center,
                    startRadius: 4,
                    endRadius: 180
                )
            )
            .blur(radius: 12)
            .allowsHitTesting(false)
    }
}

// MARK: - Motion tokens

enum PoofMotion {
    /// Snappy tap response — Music mini-player scale.
    static let quick = Animation.spring(response: 0.28, dampingFraction: 0.72)
    /// State-change bounce — Fitness ring completion.
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.62)
}

/// Fade + tiny slide-up on first appearance. Fires ONCE, then the view is
/// static — this matches how Music / Photos reveal cards on load.
/// Respects Reduce Motion → the offset + spring are skipped, only opacity
/// fades in (which is always acceptable per Apple's Human Interface Guidelines).
struct AppleEntry: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: (reduceMotion || shown) ? 0 : 12)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2).delay(delay)
                    : .spring(response: 0.55, dampingFraction: 0.85).delay(delay),
                value: shown
            )
            .onAppear { shown = true }
    }
}

extension View {
    func appleEntry(delay: Double = 0) -> some View {
        modifier(AppleEntry(delay: delay))
    }
}

// MARK: - Scroll reveal

// iOS 17+ .scrollTransition pattern — cards fade + shrink as they leave the
// viewport. Same physics Apple Music, Photos, App Store use on their vertical
// hero grids. Respects Reduce Motion (returns identity).

struct PoofScrollReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition(axis: .vertical) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .blur(radius: phase.isIdentity ? 0 : 2)
            }
        }
    }
}

extension View {
    /// Apply the Poof native scroll reveal to a card inside a ScrollView.
    func poofScrollReveal() -> some View {
        modifier(PoofScrollReveal())
    }
}

// MARK: - Pixel-perfect layer stack

// The gap between "flat CSS glass" and "Apple native glass" is a set of
// invisible micro-layers: a specular hairline that catches the top light,
// procedural grain that kills the plastic feel, an inner shadow that carves
// depth, chromatic tinting on opposite edges, a non-linear multi-stop gradient,
// a breathing glow, ambient orbs behind the hero icon. Each one is
// individually subtle — stacked, they turn a screenshot into a photograph.

// MARK: Multi-stop gradient

// A 2-stop linear gradient reads as CSS. Real Apple hero cards use 5–6 stops
// with a compressed highlight band and a darker "rebound" at the bottom —
// gives the surface a photographed feel instead of a mathematical wash.

extension PoofTheme {
    /// 5-stop non-linear vertical gradient — replaces PoofTokens.cardGradient
    /// for hero surfaces. Bright peak at ~18%, midtone at ~55%, darker rebound
    /// at 100% so a rim-light bottom overlay lands on a real shadow.
    static let heroGradientRich = LinearGradient(
        stops: [
            .init(color: PoofTokens.cardBlueTop.opacity(0.98), location: 0.00),
            .init(color: Color(red: 0.14, green: 0.52, blue: 1.00), location: 0.18),
            .init(color: PoofTokens.cardBlueTop, location: 0.42),
            .init(color: PoofTokens.cardBlueBottom, location: 0.78),
            .init(color: Color(red: 0.0, green: 0.24, blue: 0.62), location: 1.00)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: Specular hairline

// Pure-white 0.33pt line on the top edge only. Not the same as appleRimHighlight
// (which is a full-perimeter gradient stroke). This one simulates the very
// specific way the top of a glass surface catches a single light source above.

private struct SpecularHairline: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.85), .white.opacity(0.0)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    lineWidth: 0.33
                )
                .rotationEffect(.degrees(180))
                .allowsHitTesting(false)
        )
    }
}

extension View {
    /// Pure-white hairline (0.33pt) along the top edge only. Simulates
    /// a specular highlight from a light source directly above the card.
    func poofSpecularHairline(radius: CGFloat = PoofTokens.radiusCard) -> some View {
        modifier(SpecularHairline(radius: radius))
    }
}

// MARK: Noise grain

// A GPU-rendered stochastic grain overlay. Every pixel gets a low-opacity
// jitter drawn once via Canvas, then reused. 2% average opacity, softLight
// blend — reads as "photographed" instead of "vector".

private struct NoiseGrain: View {
    let intensity: Double
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 1.5
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            var rng = SystemRandomNumberGenerator()
            for y in 0 ..< rows {
                for x in 0 ..< cols {
                    let v = Double(rng.next() % 1000) / 1000.0
                    if v > 0.55 {
                        let alpha = (v - 0.55) * intensity
                        let rect = CGRect(
                            x: CGFloat(x) * cell,
                            y: CGFloat(y) * cell,
                            width: cell,
                            height: cell
                        )
                        ctx.fill(Path(rect), with: .color(.white.opacity(alpha)))
                    }
                }
            }
        }
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Procedural grain overlay. `intensity` controls the peak opacity of
    /// bright grains (0.05 = whisper, 0.15 = visible). Default 0.08 reads as
    /// "photographed" without being noisy.
    func poofNoiseGrain(
        intensity: Double = 0.08,
        radius: CGFloat = PoofTokens.radiusCard
    ) -> some View {
        overlay(
            NoiseGrain(intensity: intensity)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .allowsHitTesting(false)
        )
    }
}

// MARK: Inner shadow

// Carves depth by rendering a shadow that appears *inside* the shape's
// bottom edge — the trick is a stroke that's larger than the frame, then
// masked to the shape itself. Reads as a real 3D recess.

private struct InnerShadowBottom: ViewModifier {
    let radius: CGFloat
    let intensity: Double
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.black.opacity(intensity), lineWidth: 8)
                .blur(radius: 8)
                .offset(y: 6)
                .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .allowsHitTesting(false)
        )
    }
}

extension View {
    /// Soft inner shadow along the bottom half of the shape — gives the
    /// card a real recess feel, like Apple Wallet / Health hero surfaces.
    func poofInnerShadow(
        radius: CGFloat = PoofTokens.radiusCard,
        intensity: Double = 0.35
    ) -> some View {
        modifier(InnerShadowBottom(radius: radius, intensity: intensity))
    }
}

// MARK: Chromatic rim

// Very subtle cyan tint on the top edge and deep-blue tint on the bottom.
// Mimics chromatic aberration on real glass — the color the eye sees at
// the boundary of a refractive surface.

extension View {
    /// Two-tone rim tint: cyan sheen top, deep-blue rebound bottom.
    /// Overlays a linear gradient with .plusLighter blending at low opacity.
    func poofChromaticRim(radius: CGFloat = PoofTokens.radiusCard) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            PoofTheme.cyanGlow.opacity(0.30),
                            .clear,
                            .clear,
                            Color(red: 0.0, green: 0.20, blue: 0.55).opacity(0.35)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
    }
}

// MARK: Breathing glow

// Same footprint as AppleRadialGlow, but the opacity and scale drift on a
// 4-second loop. Fitness rings, Now Playing, Sleep glyph — Apple never lets
// its hero halos sit perfectly still.

struct AppleBreathingGlow: View {
    let color: Color
    var baseIntensity: Double = 0.45
    var swing: Double = 0.20
    var duration: Double = 4.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(reduceMotion ? baseIntensity
                            : (expanded ? baseIntensity + swing : baseIntensity)),
                        color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: reduceMotion ? 180 : (expanded ? 210 : 175)
                )
            )
            .blur(radius: 14)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
    }
}

// MARK: Ambient orbs

// Five soft orbs that drift slowly behind the hero. Deterministic seed so
// the layout is stable between launches. Position drifts on a long loop
// (10–14s per orb) using sinusoidal offsets — never mechanical.

struct PoofAmbientOrbs: View {
    var color: Color = PoofTheme.cyanGlow
    var count: Int = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: Double = 0

    struct Orb: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let phase: Double
        let speed: Double
        let amplitude: CGFloat
    }

    private var orbs: [Orb] {
        (0 ..< count).map { i in
            var g = SeededRNG(seed: UInt64(i &* 9973 &+ 17))
            return Orb(
                id: i,
                x: CGFloat.random(in: 0.15 ... 0.85, using: &g),
                y: CGFloat.random(in: 0.15 ... 0.85, using: &g),
                size: CGFloat.random(in: 38 ... 78, using: &g),
                phase: Double.random(in: 0 ... (.pi * 2), using: &g),
                speed: Double.random(in: 0.35 ... 0.62, using: &g),
                amplitude: CGFloat.random(in: 14 ... 28, using: &g)
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(orbs) { orb in
                    let dx = reduceMotion ? 0 : CGFloat(sin(t * orb.speed + orb.phase)) * orb.amplitude
                    let dy = reduceMotion ? 0 : CGFloat(cos(t * orb.speed * 0.72 + orb.phase)) * orb.amplitude * 0.7
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.55), color.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: orb.size / 2
                            )
                        )
                        .frame(width: orb.size, height: orb.size)
                        .blur(radius: 8)
                        .position(
                            x: proxy.size.width * orb.x + dx,
                            y: proxy.size.height * orb.y + dy
                        )
                }
            }
            .compositingGroup()
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                    t = .pi * 2
                }
            }
        }
    }
}

/// Simple deterministic RNG so orb layout is stable across launches.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: Composite modifier

// Applies the full "Apple photographic" stack in a stable order to any
// rounded rectangle surface. Callers shouldn't need to remember the ordering.

extension View {
    /// The full pixel-perfect stack: specular hairline + noise grain +
    /// inner shadow + chromatic rim. Apply on top of a MainCard-shaped surface.
    func poofPhotographicSurface(
        radius: CGFloat = PoofTokens.radiusCard,
        grain: Double = 0.08,
        shadow: Double = 0.32
    ) -> some View {
        poofChromaticRim(radius: radius)
            .poofInnerShadow(radius: radius, intensity: shadow)
            .poofNoiseGrain(intensity: grain, radius: radius)
            .poofSpecularHairline(radius: radius)
    }
}
