import SwiftUI

/// Comparatif Free vs Premium — tableau à 2 colonnes visuelles.
/// Chaque ligne = 1 dimension. Croix rouge / check vert pour lisibilité instantanée.
struct PaywallCompareTable: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: L10n
        let freeAllowed: Bool
        let premiumAllowed: Bool
        let freeHint: L10n?
        let premiumHint: L10n?
    }

    static let rows: [Row] = [
        Row(
            label: L10n(fr: "Envoi cross-platform", en: "Cross-platform send"),
            freeAllowed: true, premiumAllowed: true,
            freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Taille par fichier", en: "File size"),
            freeAllowed: true, premiumAllowed: true,
            freeHint: L10n(fr: "500 Mo", en: "500 MB"),
            premiumHint: L10n(fr: "50 Go", en: "50 GB")
        ),
        Row(
            label: L10n(fr: "History", en: "History"),
            freeAllowed: true, premiumAllowed: true,
            freeHint: L10n(fr: "24 h", en: "24 h"),
            premiumHint: L10n(fr: "Illimité", en: "Unlimited")
        ),
        Row(
            label: L10n(fr: "Chiffrement E2E", en: "End-to-end encryption"),
            freeAllowed: true, premiumAllowed: true,
            freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Mot de passe et expiration", en: "Passcode and expiry"),
            freeAllowed: false, premiumAllowed: true, freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Accusés de lecture et push", en: "Read receipts and push"),
            freeAllowed: false, premiumAllowed: true, freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Envoi offline (BT, mesh)", en: "Offline send (BT, mesh)"),
            freeAllowed: false, premiumAllowed: true, freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Encode auto TikTok, Reels, Shorts", en: "Auto-encode TikTok, Reels, Shorts"),
            freeAllowed: false, premiumAllowed: true, freeHint: nil, premiumHint: nil
        ),
        Row(
            label: L10n(fr: "Multi-destinataires", en: "Multi-recipient"),
            freeAllowed: false, premiumAllowed: true, freeHint: nil, premiumHint: nil
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(Self.rows.enumerated()), id: \.element.id) { idx, row in
                rowView(row)
                    .background(
                        Color.white.opacity(idx.isMultiple(of: 2) ? 0.03 : 0)
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Sub views

    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            columnLabel(L10n(fr: "Gratuit", en: "Free").localized, isPremium: false)
                .frame(width: 92)
            columnLabel(L10n(fr: "Premium", en: "Premium").localized, isPremium: true)
                .frame(width: 92)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
    }

    private func columnLabel(_ text: String, isPremium: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(isPremium ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 0) {
            Text(row.label.localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            cell(allowed: row.freeAllowed, hint: row.freeHint?.localized, isPremium: false)
                .frame(width: 92)
            cell(allowed: row.premiumAllowed, hint: row.premiumHint?.localized, isPremium: true)
                .frame(width: 92)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func cell(allowed: Bool, hint: String?, isPremium: Bool) -> some View {
        VStack(spacing: 3) {
            if allowed {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isPremium ? .white : .white.opacity(0.55))
            } else {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.30))
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(isPremium ? 0.85 : 0.55))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
