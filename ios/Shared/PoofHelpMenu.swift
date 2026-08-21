import SwiftUI

// Sheet hub — 2 grandes cartes : FAQ (lire les réponses) et Fix bug & idée
// (envoyer un message au support). Ouverte depuis SecondCard sur Home.

struct PoofHelpMenu: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFAQ = false
    @State private var showChat = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                VStack(spacing: 16) {
                    optionCard(
                        icon: "questionmark.bubble.fill",
                        title: "FAQ",
                        subtitle: "Answers to the most frequent questions."
                    ) {
                        PoofHaptics.tap()
                        showFAQ = true
                    }

                    optionCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Bug fix & improvement",
                        subtitle: "Report a bug or suggest an idea — we'll get back."
                    ) {
                        PoofHaptics.tap()
                        showChat = true
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showFAQ) {
            PoofFAQView()
        }
        .sheet(isPresented: $showChat) {
            PoofSupportChat()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Aide & Feedback")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Option card

    private func optionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FAQ view

struct PoofFAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: UUID?

    private struct FAQ: Identifiable {
        let id = UUID()
        let q: String
        let a: String
    }

    private let faqs: [FAQ] = [
        FAQ(
            q: "How do I send a file?",
            a: "Open the Send tab, pick a type (photo, doc, clipboard), select a recipient, then swipe the central circle upward."
        ),
        FAQ(
            q: "Are my files encrypted?",
            a: "Yes. All transfers go peer-to-peer via WebRTC. Secure (Premium) adds an extra AES-256 layer on the file itself."
        ),
        FAQ(
            q: "Why isn't my file sending?",
            a: "Check that your recipient is online (green dot) and Poof is open on both sides. On Free, Poof stays limited to your local Wi-Fi."
        ),
        FAQ(
            q: "How do I pair a new device?",
            a: "Send tab → tap an empty slot → Add device sheet → scan the QR or enter the code shown on the other device."
        ),
        FAQ(
            q: "How does Premium work?",
            a: "Premium unlocks Secure, Track, Boost, Offline and Studio. 7-day free trial, cancellable from iCloud Settings."
        ),
        FAQ(
            q: "Can I recover an expired file?",
            a: "No. Secure files with expiry are removed locally + from the Photos gallery if saved. That's the « auto-destruct » promise."
        ),
        FAQ(
            q: "Where do I see my send history?",
            a: "Onglet Received → tap sur « All history » pour voir Sent / Received / Clipboard, avec la date et le destinataire."
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0 / 255, green: 94 / 255, blue: 255 / 255),
                    Color(red: 121 / 255, green: 121 / 255, blue: 121 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(faqs) { faq in
                            faqRow(faq)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("FAQ")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func faqRow(_ faq: FAQ) -> some View {
        let isOpen = expanded == faq.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                PoofHaptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded = isOpen ? nil : faq.id
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(faq.q)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.70))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(faq.a)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                )
        )
    }
}

#Preview {
    PoofHelpMenu()
}
