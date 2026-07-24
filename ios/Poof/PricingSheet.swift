import SwiftUI

// Pricing modal — shows all 5 tiers with features + CTAs.
// Selecting a tier updates @AppStorage("poof.tier"), which auto-adapts
// the whole app's accent + background glow.

struct PricingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoofTier.storageKey) private var tierRaw: String = PoofTier.free.rawValue

    private var currentTier: PoofTier { PoofTier(rawValue: tierRaw) ?? .free }

    var body: some View {
        NavigationStack {
            ZStack {
                PoofBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        ForEach(PoofTier.allCases) { t in
                            tierCard(t)
                        }
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(PoofTheme.textSecondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Choose your plan")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(PoofTheme.textPrimary)
            Text("Zero cloud. Pure P2P. E2E on every tier.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func tierCard(_ t: PoofTier) -> some View {
        let isCurrent = t == currentTier
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(t.accent).frame(width: 10, height: 10)
                    Text(t.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(PoofTheme.textPrimary)
                }
                Spacer()
                Text(t.priceLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(t.accent)
            }
            Text(t.tagline)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PoofTheme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features(for: t), id: \.self) { line in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(t.accent)
                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(PoofTheme.textPrimary.opacity(0.86))
                        Spacer()
                    }
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                    tierRaw = t.rawValue
                }
            } label: {
                Text(isCurrent ? "Current plan" : ctaLabel(for: t))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isCurrent ? PoofTheme.textSecondary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            isCurrent
                            ? AnyShapeStyle(Color.white.opacity(0.08))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [t.accent, t.glow],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                    )
            }
            .disabled(isCurrent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: PoofTheme.radiusLg)
        .overlay(
            RoundedRectangle(cornerRadius: PoofTheme.radiusLg)
                .strokeBorder(isCurrent ? t.accent.opacity(0.6) : Color.clear, lineWidth: 1.2)
        )
    }

    private func ctaLabel(for t: PoofTier) -> String {
        switch t {
        case .free:     return "Downgrade to Free"
        case .premium:  return "Start 7-day free trial"
        case .family:   return "Get Family"
        case .devium:   return "Get Devium"
        case .business: return "Contact sales"
        }
    }

    private func features(for t: PoofTier) -> [String] {
        switch t {
        case .free:
            return [
                "2 paired devices",
                "Files up to 2 GB",
                "Universal Clipboard (text, LAN)",
                "End-to-end encryption",
                "Unlimited transfers"
            ]
        case .premium:
            return [
                "Unlimited paired devices",
                "Folders — no size limit",
                "Universal Clipboard everywhere",
                "Remote Files (browse from anywhere)",
                "Hot Folders (auto-sync)",
                "Screen Mirror",
                "Read receipts"
            ]
        case .family:
            return [
                "Everything in Premium",
                "4 accounts included",
                "Family Room (shared drop zone)",
                "Parental Poof Wall",
                "Kid-friendly device limits"
            ]
        case .devium:
            return [
                "Everything in Premium",
                "CLI  (poof send file.zip alice@mac)",
                "API keys for CI/CD",
                "Multi-Drop broadcast",
                "SSH key injection",
                "Webhook triggers",
                "Air-gapped mode"
            ]
        case .business:
            return [
                "Everything in Premium",
                "SSO (SAML / OIDC)",
                "Admin dashboard",
                "Audit logs",
                "Team rooms",
                "Custom branding",
                "Priority support"
            ]
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Cancel anytime. Data never leaves your devices.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PoofTheme.textTertiary)
        }
        .padding(.top, 6)
    }
}
