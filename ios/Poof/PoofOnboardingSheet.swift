import SwiftUI

/// Onboarding première ouverture — 4 slides swipeable dans l'identité
/// visuelle globale de Poof (gradient bleu → gris, glass, accent cyan).
/// Set `PoofSession.hasOnboarded` à la fin pour ne plus jamais réafficher.
struct PoofOnboardingSheet: View {
    @EnvironmentObject var session: PoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0

    private struct Slide: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let subtitle: String
    }

    private let slides: [Slide] = [
        Slide(
            id: 0,
            icon: "paperplane.fill",
            title: "Welcome to Poof",
            subtitle: "Send photos, videos and files to any of your devices, instantly."
        ),
        Slide(
            id: 1,
            icon: "iphone.radiowaves.left.and.right",
            title: "Pair without a code",
            subtitle: "Open Poof on both sides — your iPhone and Mac see each other nearby. One tap, one accept, done."
        ),
        Slide(
            id: 2,
            icon: "lock.shield.fill",
            title: "Private by design",
            subtitle: "End-to-end encrypted. No account required. Your files never sit on our servers."
        ),
        Slide(
            id: 3,
            icon: "gift.fill",
            title: "Early supporter",
            subtitle: "Send 20 files during the beta and unlock 1 month of Premium free at launch."
        )
    ]

    var body: some View {
        ZStack {
            background
            content
            topBar
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(slides) { slide in
                    slideView(slide)
                        .tag(slide.id)
                        .padding(.horizontal, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomControls
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .padding(.top, 60)
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            hero(icon: slide.icon)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Spacer()
        }
    }

    private func hero(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.02)
                        ],
                        center: .center, startRadius: 6, endRadius: 90
                    )
                )
                .frame(width: 200, height: 200)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 10 / 255, green: 226 / 255, blue: 255 / 255),
                            Color(red: 0 / 255, green: 0 / 255, blue: 255 / 255)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 118, height: 118)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.20), radius: 12, y: 6)

            Image(systemName: icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 3)
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 18) {
            pageIndicator
            actionButton
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(slides) { slide in
                Capsule()
                    .fill(currentPage == slide.id ? Color.white : Color.white.opacity(0.32))
                    .frame(width: currentPage == slide.id ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
            }
        }
    }

    private var actionButton: some View {
        Button {
            PoofHaptics.impactMedium()
            if currentPage < slides.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } else {
                finish()
            }
        } label: {
            Text(currentPage < slides.count - 1 ? "Next" : "Get started")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Top bar (Skip)

    @ViewBuilder
    private var topBar: some View {
        if currentPage < slides.count - 1 {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        PoofHaptics.tap()
                        finish()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.28)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func finish() {
        session.completeOnboarding()
        dismiss()
    }

    // MARK: - Deep link helpers (utilisés par PairingSheet pour un pair via URL)

    static func parseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }
}
