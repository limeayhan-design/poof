import SwiftUI

// Reusable "Upgrade to Premium" gate — Ripples style.
// Drop-in replacement for a feature body when the current tier can't access it.
// The CTA fires .poofOpenPricing, PoofRootView routes it to the paywall sheet.

extension Notification.Name {
    static let poofOpenPricing = Notification.Name("poof.openPricing")
    // App Intents (Action Button / Siri / Shortcuts) postent ces notifs
    // pour router vers les mêmes flows qu'un tap manuel. Le routing est
    // fait dans PoofRootView.AppIntentsWiring.
    static let poofSendClipboard = Notification.Name("poof.sendClipboard")
    static let poofOpenSend = Notification.Name("poof.openSend")
    static let poofOpenPairing = Notification.Name("poof.openPairing")
}

struct PaywallLockedView: View {
    let icon: String
    let title: String
    let subtitle: String
    var dismissOnTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(RipplesTokens.violetAccent)
                .frame(width: 96, height: 96)
                .background(
                    Circle().fill(RipplesTokens.violetAccent.opacity(0.15))
                )

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                PoofHaptics.tap()
                dismissOnTap?()
                NotificationCenter.default.post(name: .poofOpenPricing, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Upgrade to Premium")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)

            Text("Included in Premium · €4.99/mo · 7-day free trial")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RipplesTokens.background.ignoresSafeArea())
    }
}

/// Convenience — small inline pill for gating a specific control (toggle, row).
struct PaywallLockPill: View {
    var action: () -> Void = {
        NotificationCenter.default.post(name: .poofOpenPricing, object: nil)
    }

    var body: some View {
        Button {
            PoofHaptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("PREMIUM")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(RipplesTokens.violetAccent))
        }
        .buttonStyle(.plain)
    }
}
