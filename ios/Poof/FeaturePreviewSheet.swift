import SwiftUI

// Reusable sheet used everywhere a tier feature is either shipped, in preview,
// or coming soon. Replaces the "dead button" experience across tier sections.

enum FeatureStatus {
    case available
    case preview
    case comingSoon

    var label: String {
        switch self {
        case .available: "Available now"
        case .preview: "Preview"
        case .comingSoon: "Coming soon"
        }
    }

    var color: Color {
        switch self {
        case .available: PoofTheme.green
        case .preview: PoofTheme.accent2
        case .comingSoon: PoofTheme.textSecondary
        }
    }
}

struct FeaturePreview: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let tagline: String
    let status: FeatureStatus
    let description: String
    let accent: Color
}

struct FeaturePreviewSheet: View {
    let preview: FeaturePreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(preview.status.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(preview.status.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(preview.status.color.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(preview.status.color.opacity(0.32), lineWidth: 1))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PoofTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Image(systemName: preview.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 84, height: 84)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [preview.accent, preview.accent.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: preview.accent.opacity(0.35), radius: 22, x: 0, y: 10)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Text(preview.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PoofTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(preview.tagline)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PoofTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            Text(preview.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PoofTheme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 12)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    if preview.status != .available {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(preview.status == .available ? "Got it" : "Notify me when live")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: PoofTheme.radiusMd, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [preview.accent, preview.accent.opacity(0.7)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PoofTheme.bgBase.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Small "Preview" pill used in tier section headers to be honest about mocks.
struct PreviewPill: View {
    let accent: Color
    var body: some View {
        Text("Preview")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(accent.opacity(0.14)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
    }
}
