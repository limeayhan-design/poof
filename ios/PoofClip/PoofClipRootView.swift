import AppClip
import StoreKit
import SwiftUI

// Landing UI shown inside the App Clip card. Big hero with sender name +
// filename hint, one primary CTA that either deep-links into the installed
// Poof app or triggers an App Store overlay to install it. The overlay is
// Apple's recommended pattern: the user never leaves the Clip context.

struct PoofClipRootView: View {
    let pairCode: String?
    let peerName: String

    @State private var showAppStoreOverlay = false

    private var glassGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.48, blue: 1.00),
                Color(red: 0.06, green: 0.11, blue: 0.28)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            glassGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                heroCard
                    .padding(.horizontal, 20)

                Spacer(minLength: 24)

                primaryCTA
                    .padding(.horizontal, 20)

                installHint
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
        .appStoreOverlay(isPresented: $showAppStoreOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 116, height: 116)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(
                        color: Color(red: 0.35, green: 0.80, blue: 1.00).opacity(0.55),
                        radius: 22,
                        y: 0
                    )
            }
            .padding(.top, 30)

            VStack(spacing: 6) {
                Text("A file for you")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("from \(peerName)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }

    private var primaryCTA: some View {
        Button {
            openInApp()
        } label: {
            Text("Open Poof to receive")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.06, green: 0.11, blue: 0.28))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(Color.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var installHint: some View {
        Text("Poof isn't installed? Tap the App Store card below to get it in one tap.")
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
    }

    private func openInApp() {
        var comps = URLComponents()
        comps.scheme = "poof"
        comps.host = ""
        comps.path = ""
        var items: [URLQueryItem] = []
        if let code = pairCode, !code.isEmpty {
            items.append(URLQueryItem(name: "pair", value: code))
        }
        comps.queryItems = items.isEmpty ? nil : items

        // `poof://?pair=CODE` opens the installed app straight into pairing.
        // If Poof isn't installed, the URL fails silently and we flip the
        // App Store overlay on so the user can install with one tap.
        if let url = comps.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            showAppStoreOverlay = true
        }
    }
}
