import ActivityKit
import SwiftUI
import WidgetKit

// Poof Live Activity — Lock Screen + Dynamic Island premium. Design pilier :
// hero avatar glow, progress ring / linear gradient, speed + ETA live,
// hairline glass. Palette hand-inlined (widget target n'importe pas
// PoofTokens).

private enum PoofWidgetPalette {
    static let bgTop = Color(red: 0.02, green: 0.09, blue: 0.28) // #051772
    static let bgBottom = Color(red: 0.01, green: 0.02, blue: 0.10) // #030519
    static let accentTop = Color(red: 0.35, green: 0.75, blue: 1.00) // #59BFFF
    static let accentMid = Color(red: 0.42, green: 0.55, blue: 1.00) // #6B8CFF
    static let accentEnd = Color(red: 0.60, green: 0.35, blue: 1.00) // #995AFF
    static let successGlow = Color(red: 0.20, green: 0.90, blue: 0.55) // #33E68C
    static let errorGlow = Color(red: 1.00, green: 0.30, blue: 0.35) // #FF4D59
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.10)
}

struct PoofTransferLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PoofTransferAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandAvatar(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandPercent(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(context: context)
                }
            } compactLeading: {
                CompactLeading(context: context)
            } compactTrailing: {
                CompactTrailing(context: context)
            } minimal: {
                MinimalRing(context: context)
            }
            .keylineTint(accentColor(for: context))
        }
    }
}

// MARK: - Shared helpers

private func accentColor(for context: ActivityViewContext<PoofTransferAttributes>) -> Color {
    if context.state.didFail {
        return PoofWidgetPalette.errorGlow
    }
    if context.state.isFinished {
        return PoofWidgetPalette.successGlow
    }
    return PoofWidgetPalette.accentTop
}

private func glyph(_ direction: PoofTransferAttributes.Direction) -> String {
    switch direction {
    case .send: "paperplane.fill"
    case .receive: "tray.and.arrow.down.fill"
    }
}

private func headline(_ context: ActivityViewContext<PoofTransferAttributes>) -> String {
    if context.state.didFail {
        return "Transfer failed"
    }
    if context.state.isFinished {
        return context.attributes.direction == .send ? "Sent to \(context.attributes.peerName)" : "Received from \(context.attributes.peerName)"
    }
    return context.attributes.direction == .send ? "Sending to \(context.attributes.peerName)" : "Receiving from \(context.attributes.peerName)"
}

private func percentInt(_ context: ActivityViewContext<PoofTransferAttributes>) -> Int {
    let f = context.state.fraction(of: context.attributes.totalBytes)
    return Int((f * 100).rounded())
}

private func percentString(_ context: ActivityViewContext<PoofTransferAttributes>) -> String {
    if context.state.didFail {
        return "!"
    }
    if context.state.isFinished {
        return "100%"
    }
    return "\(percentInt(context))%"
}

private func bytesString(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private func speedString(_ context: ActivityViewContext<PoofTransferAttributes>) -> String {
    let elapsed = Date().timeIntervalSince(context.attributes.startedAt)
    guard elapsed > 0.5, context.state.received > 0, !context.state.isFinished, !context.state.didFail else {
        return context.state.isFinished ? "Complete" : "—"
    }
    let bps = Double(context.state.received) / elapsed
    return "\(bytesString(UInt64(bps)))/s"
}

private func etaDate(_ context: ActivityViewContext<PoofTransferAttributes>) -> Date? {
    let elapsed = Date().timeIntervalSince(context.attributes.startedAt)
    guard elapsed > 0.8, context.state.received > 0, !context.state.isFinished,
          !context.state.didFail else { return nil }
    let bps = Double(context.state.received) / elapsed
    guard bps > 0 else { return nil }
    let remainingBytes = Double(context.attributes.totalBytes) - Double(context.state.received)
    guard remainingBytes > 0 else { return nil }
    let seconds = remainingBytes / bps
    return Date().addingTimeInterval(seconds)
}

// MARK: - Dynamic Island — Compact

private struct CompactLeading: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor(for: context).opacity(0.20))
                .frame(width: 22, height: 22)
            Image(systemName: glyph(context.attributes.direction))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accentColor(for: context))
        }
    }
}

private struct CompactTrailing: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .trim(from: 0, to: context.state.fraction(of: context.attributes.totalBytes))
                .stroke(
                    accentColor(for: context),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 22, height: 22)
            Text("\(percentInt(context))")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoofWidgetPalette.textPrimary)
        }
    }
}

private struct MinimalRing: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: context.state.fraction(of: context.attributes.totalBytes))
                .stroke(
                    accentColor(for: context),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Dynamic Island — Expanded

private struct IslandAvatar: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor(for: context).opacity(0.35),
                            accentColor(for: context).opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
            Image(systemName: glyph(context.attributes.direction))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accentColor(for: context))
        }
    }
}

private struct IslandPercent: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        Text(percentString(context))
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(PoofWidgetPalette.textPrimary)
            .padding(.trailing, 4)
    }
}

private struct IslandCenter: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline(context))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PoofWidgetPalette.textSecondary)
                .lineLimit(1)
            Text(context.attributes.fileName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PoofWidgetPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IslandBottom: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        VStack(spacing: 8) {
            GradientProgressBar(
                fraction: context.state.fraction(of: context.attributes.totalBytes),
                tint: accentColor(for: context),
                height: 5
            )

            HStack(spacing: 6) {
                stat(icon: "bolt.fill", text: speedString(context))
                Circle().fill(PoofWidgetPalette.textTertiary).frame(width: 3, height: 3)
                if let eta = etaDate(context) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PoofWidgetPalette.textSecondary)
                        Text(timerInterval: Date() ... eta, countsDown: true)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PoofWidgetPalette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                stat(icon: nil, text: bytesString(context.attributes.totalBytes))
            }
        }
        .padding(.top, 4)
    }

    private func stat(icon: String?, text: String) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PoofWidgetPalette.textSecondary)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoofWidgetPalette.textSecondary)
        }
    }
}

// MARK: - Progress bar

private struct GradientProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.85),
                                tint,
                                PoofWidgetPalette.accentEnd
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * fraction))
                    .shadow(color: tint.opacity(0.55), radius: 4, y: 0)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<PoofTransferAttributes>

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 14) {
                headerRow
                progressBlock
                statsRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Sub views

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [PoofWidgetPalette.bgTop, PoofWidgetPalette.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Halo accent en haut-gauche pour animer le fond.
            RadialGradient(
                colors: [tint.opacity(0.35), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [PoofWidgetPalette.accentEnd.opacity(0.25), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(context))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoofWidgetPalette.textSecondary)
                    .lineLimit(1)
                Text(context.attributes.fileName)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(PoofWidgetPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Text(percentString(context))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoofWidgetPalette.textPrimary)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.38), tint.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
                .shadow(color: tint.opacity(0.55), radius: 10, y: 2)
            Image(systemName: glyph(context.attributes.direction))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PoofWidgetPalette.textPrimary)
        }
    }

    private var progressBlock: some View {
        GradientProgressBar(
            fraction: context.state.fraction(of: context.attributes.totalBytes),
            tint: tint,
            height: 7
        )
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(icon: "bolt.fill", label: "Speed", value: speedString(context))

            Divider()
                .frame(height: 22)
                .overlay(PoofWidgetPalette.hairline)
                .padding(.horizontal, 12)

            etaCell

            Divider()
                .frame(height: 22)
                .overlay(PoofWidgetPalette.hairline)
                .padding(.horizontal, 12)

            statCell(icon: "doc.fill", label: "Size", value: bytesString(context.attributes.totalBytes))
        }
    }

    private var etaCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ETA")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(PoofWidgetPalette.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            if let eta = etaDate(context) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PoofWidgetPalette.textPrimary)
                    Text(timerInterval: Date() ... eta, countsDown: true)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PoofWidgetPalette.textPrimary)
                }
            } else {
                Text(context.state.isFinished ? "Done" : "—")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(PoofWidgetPalette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statCell(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(PoofWidgetPalette.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PoofWidgetPalette.textPrimary)
                Text(value)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PoofWidgetPalette.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        accentColor(for: context)
    }
}
