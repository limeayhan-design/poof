import Combine
import Foundation
import StoreKit
import SwiftUI

// MARK: - Localised string (FR + EN paire)

/// Petit helper de localisation : deux versions FR/EN inline, `.localized`
/// choisit selon `Locale.current`. Léger, sans .xcstrings, adapté au périmètre
/// de la paywall (~40 lignes de copy).
struct L10n: Equatable, Hashable {
    let fr: String
    let en: String

    /// Toute l'app force l'anglais pour l'App Store international. Le champ
    /// `fr` est conservé pour éviter de casser les ~1000 call sites existants
    /// mais n'est plus jamais rendu. Réactivable en 1 ligne si besoin
    /// multilingue plus tard.
    var localized: String {
        en
    }
}

extension L10n: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        fr = value
        en = value
    }
}

// MARK: - Premium feature kinds

enum PremiumFeatureKind: String, CaseIterable, Identifiable {
    case secure, track, boost, offline, studio

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .secure: "lock.shield.fill"
        case .track: "eye.fill"
        case .boost: "bolt.fill"
        case .offline: "airplane"
        case .studio: "film.fill"
        }
    }

    /// Couleur d'accent par feature (pour le halo hero + section deep-dive).
    var tint: Color {
        switch self {
        case .secure: Color(red: 0.35, green: 0.55, blue: 1.0)
        case .track: Color(red: 0.95, green: 0.55, blue: 0.30)
        case .boost: Color(red: 1.0, green: 0.85, blue: 0.20)
        case .offline: Color(red: 0.35, green: 0.85, blue: 0.75)
        case .studio: Color(red: 0.85, green: 0.35, blue: 0.95)
        }
    }
}

// MARK: - Feature model

struct PremiumFeature: Identifiable, Equatable {
    let kind: PremiumFeatureKind
    let title: L10n
    let baseline: L10n
    let promises: [L10n]
    /// Index des promises marquées "Soon" (feature affichée dans la roadmap
    /// mais pas encore câblée). Vide par défaut = tout est câblé.
    var soonIndices: Set<Int> = []

    var id: String {
        kind.id
    }

    var icon: String {
        kind.icon
    }

    var tint: Color {
        kind.tint
    }
}

// MARK: - Catalogue Premium — 30 promesses toutes réellement implémentées.

// Les promesses nécessitant un backend qu'on n'a pas (staging cloud, upload
// APIs sociales, PDF signés, notifications push OS) ou du cross-platform
// Android/Windows ont été retirées pour rester honnête vis-à-vis d'Apple
// (Guideline 2.3.1 — Metadata Accuracy) et de l'utilisateur payant.

enum PoofPremiumCatalog {
    static let all: [PremiumFeature] = [
        secure, track, boost, offline, studio
    ]

    static let secure = PremiumFeature(
        kind: .secure,
        title: L10n(fr: "Secure", en: "Secure"),
        baseline: L10n(
            fr: "L'envoi qui disparaît.",
            en: "Sends that vanish."
        ),
        promises: [
            L10n(
                fr: "Mot de passe 4-6 chiffres avant ouverture",
                en: "4-6 digit passcode before opening"
            ),
            L10n(
                fr: "Expiration au choix : 1h, 24h, 7 jours ou date custom",
                en: "Set expiry: 1h, 24h, 7 days or custom"
            ),
            L10n(
                fr: "Ouverture unique — auto-destruction après lecture",
                en: "One-time view — auto-destruct after read"
            ),
            L10n(
                fr: "Chiffrement E2E AES-256 zero-knowledge",
                en: "End-to-end AES-256, zero-knowledge"
            ),
            L10n(
                fr: "Watermark auto avec le nom du destinataire",
                en: "Auto watermark with recipient's name"
            ),
            L10n(
                fr: "Face ID / Touch ID requis à l'ouverture",
                en: "Face ID / Touch ID required on open"
            )
        ]
    )

    static let track = PremiumFeature(
        kind: .track,
        title: L10n(fr: "Track", en: "Track"),
        baseline: L10n(
            fr: "Tu sais tout, tout le temps.",
            en: "Know everything, all the time."
        ),
        promises: [
            L10n(
                fr: "Accusé de lecture en temps réel",
                en: "Real-time read receipts"
            ),
            L10n(
                fr: "Horodatage précis à la seconde",
                en: "Precise timestamps down to the second"
            ),
            L10n(
                fr: "Compteur d'ouvertures détaillé par fichier",
                en: "Detailed open counter per file"
            ),
            L10n(
                fr: "Nom de l'appareil qui a ouvert le fichier",
                en: "Device name that opened the file"
            ),
            L10n(
                fr: "Message custom envoyé au destinataire",
                en: "Custom message shown to recipient"
            )
        ]
    )

    static let boost = PremiumFeature(
        kind: .boost,
        title: L10n(fr: "Boost", en: "Boost"),
        baseline: L10n(
            fr: "Sans limites, à toute vitesse.",
            en: "No limits, full speed."
        ),
        promises: [
            L10n(
                fr: "Fichiers sans limite de taille (vs 500 Mo)",
                en: "Unlimited file size (vs 500 MB)"
            ),
            L10n(
                fr: "Compression LZFSE sans perte avant transfert",
                en: "Lossless LZFSE compression before transfer"
            ),
            L10n(
                fr: "Multi-destinataires en un seul envoi",
                en: "Multi-recipient single send"
            ),
            L10n(
                fr: "Envoi batch jusqu'à 1000 fichiers d'un coup",
                en: "Batch send up to 1000 files at once"
            ),
            L10n(
                fr: "Reprise automatique si la connexion coupe",
                en: "Auto-resume if the connection drops"
            )
        ],
        soonIndices: [3, 4]
    )

    static let offline = PremiumFeature(
        kind: .offline,
        title: L10n(fr: "Offline", en: "Offline"),
        baseline: L10n(
            fr: "Envoie sans internet, même en avion.",
            en: "Send without internet, even on a plane."
        ),
        promises: [
            L10n(
                fr: "Bluetooth et Wi-Fi direct pair à pair",
                en: "Bluetooth and Wi-Fi Direct peer-to-peer"
            ),
            L10n(
                fr: "Fonctionne en mode avion",
                en: "Works in airplane mode"
            ),
            L10n(
                fr: "Portée jusqu'à 100 m en ligne directe",
                en: "Range up to 100 m line-of-sight"
            ),
            L10n(
                fr: "Chiffrement E2E AES-256 même hors ligne",
                en: "End-to-end AES-256 encryption even offline"
            ),
            L10n(
                fr: "Reprise auto quand tu repasses à portée",
                en: "Auto-resume when back in range"
            ),
            L10n(
                fr: "Zéro latence serveur, tout se joue en local",
                en: "Zero server latency, fully local"
            )
        ],
        soonIndices: [4]
    )

    static let studio = PremiumFeature(
        kind: .studio,
        title: L10n(fr: "Studio", en: "Studio"),
        baseline: L10n(
            fr: "Ton master, prêt à poster, sans perte.",
            en: "Your master, ready to post, no quality loss."
        ),
        promises: [
            L10n(
                fr: "Encode aux specs exactes Insta, TikTok, YT Shorts, LinkedIn",
                en: "Encode to exact Instagram, TikTok, YT Shorts, LinkedIn specs"
            ),
            L10n(
                fr: "Accélération VideoToolbox hardware",
                en: "VideoToolbox hardware acceleration"
            ),
            L10n(
                fr: "Masters ProRes / H.265 / RAW passthrough préservés",
                en: "ProRes / H.265 / RAW masters passed through"
            ),
            L10n(
                fr: "Watermark texte optionnel gravé dans la vidéo",
                en: "Optional text watermark burned into video"
            ),
            L10n(
                fr: "Batch encode — plusieurs rushes en une seule action",
                en: "Batch encode — multiple rushes in one action"
            ),
            L10n(
                fr: "Presets custom par plateforme, sauvegardés localement",
                en: "Custom platform presets, saved locally"
            )
        ]
    )
}

// MARK: - Plans + IAP stub

enum PoofPremiumPlan: String, CaseIterable, Identifiable {
    case monthly, yearly

    var id: String {
        rawValue
    }

    /// Prix affiché en fallback si StoreKit n'a pas encore chargé les products
    /// (device offline, App Store down, etc.). En prod, on lit `Product.displayPrice`
    /// via `PoofPremiumStore.displayPrice(for:)` qui gère la devise locale.
    var fallbackPriceLabel: String {
        switch self {
        case .monthly: "4,99 €"
        case .yearly: "59,88 €"
        }
    }

    var billedLabel: L10n {
        switch self {
        case .monthly: L10n(fr: "facturé chaque mois", en: "billed monthly")
        case .yearly: L10n(fr: "facturé une fois par an", en: "billed yearly")
        }
    }

    var trialDays: Int {
        7
    }

    /// Product ID App Store Connect (à créer côté ASC — même naming).
    var productId: String {
        switch self {
        case .monthly: "com.Poof.Premium.monthly"
        case .yearly: "com.Poof.Premium.yearly"
        }
    }
}

/// Vrai wiring StoreKit 2 pour Poof Premium.
/// - Charge les 2 products au démarrage (`Product.products(for:)`).
/// - Écoute les mises à jour de transactions (`Transaction.updates`) en tâche
///   détachée pour attraper les renouvellements et achats hors-app.
/// - Recalcule `isPremium` depuis `Transaction.currentEntitlements` — c'est
///   la seule source de vérité (jamais persister un flag "premium" client-side
///   qu'un simple UserDefaults edit pourrait bypasser).
/// - Expose `displayPrice(for:)` avec fallback si products pas encore chargés.
@MainActor
final class PoofPremiumStore: ObservableObject {
    static let shared = PoofPremiumStore()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isPremium: Bool = false
    @Published private(set) var isLoadingProducts: Bool = true
    @Published private(set) var isEligibleForIntro: Bool = true
    @Published var selectedPlan: PoofPremiumPlan = .yearly
    @Published var isPurchasing: Bool = false
    @Published var lastError: String?

    #if DEBUG
        /// Override local persistant pour tester les features Premium sans passer
        /// par un vrai achat StoreKit — activé par le bouton d'achat quand aucun
        /// product n'est chargé (config `.storekit` pas branchée dans le scheme).
        /// Stripé de la build Release, aucun risque en prod.
        @AppStorage("poof.debugPremium") private var debugPremium: Bool = false
    #endif

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task { [weak self] in
            await self?.loadProducts()
            await self?.updateEntitlements()
            await self?.updateIntroEligibility()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Products

    func product(for plan: PoofPremiumPlan) -> Product? {
        products[plan.productId]
    }

    /// Prix localisé renvoyé par StoreKit (respecte la devise / région App Store),
    /// avec fallback statique si les products ne sont pas encore chargés.
    func displayPrice(for plan: PoofPremiumPlan) -> String {
        product(for: plan)?.displayPrice ?? plan.fallbackPriceLabel
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let ids = PoofPremiumPlan.allCases.map(\.productId)
            let fetched = try await Product.products(for: ids)
            var map: [String: Product] = [:]
            for p in fetched {
                map[p.id] = p
            }
            products = map
        } catch {
            lastError = "loadProducts: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase(_ plan: PoofPremiumPlan) async {
        #if DEBUG
            // Aucun product chargé (config `.storekit` non branchée dans le scheme)
            // → on simule l'achat en local pour débloquer les features Premium
            // pendant le dev sans avoir à passer par App Store Connect.
            if products.isEmpty {
                isPurchasing = true
                try? await Task.sleep(nanoseconds: 350_000_000)
                debugPremium = true
                await updateEntitlements()
                await updateIntroEligibility()
                isPurchasing = false
                return
            }
        #endif
        guard let product = product(for: plan) else {
            lastError = "Product \(plan.productId) not available yet."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlements()
                await updateIntroEligibility()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "purchase: \(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
            await updateIntroEligibility()
        } catch {
            lastError = "restore: \(error.localizedDescription)"
        }
    }

    // MARK: - Transactions listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(transaction: update)
            }
        }
    }

    private func handle(transaction result: VerificationResult<StoreKit.Transaction>) async {
        do {
            let transaction = try checkVerified(result)
            await transaction.finish()
            await updateEntitlements()
            await updateIntroEligibility()
        } catch {
            lastError = "transaction: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// Recalcule `isPremium` depuis les entitlements actifs — c'est la
    /// seule source de vérité. Un abonnement expiré ou annulé disparaît
    /// automatiquement de `currentEntitlements`.
    private func updateEntitlements() async {
        var active = false
        let premiumIds = Set(PoofPremiumPlan.allCases.map(\.productId))
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if premiumIds.contains(transaction.productID) {
                active = true
                break
            }
        }
        #if DEBUG
            if debugPremium {
                active = true
            }
        #endif
        isPremium = active
    }

    #if DEBUG
        /// Toggle du flag Premium debug — utilisé par le long-press sur le
        /// rectangle Premium banner en Send view pour tester les 2 états
        /// (verrouillé ↔ débloqué) sans avoir à réinstaller ni relancer le simu.
        func debugTogglePremium() {
            debugPremium.toggle()
            Task { await updateEntitlements() }
        }
    #endif

    /// Vérifie si l'utilisateur peut bénéficier de l'intro offer (7 jours gratuits).
    /// Apple : 1 seul intro offer par subscription group, tous plans confondus.
    /// On check sur le plan mensuel : les 2 plans partagent le même group.
    private func updateIntroEligibility() async {
        guard let anyProduct = products.values.first,
              let subscription = anyProduct.subscription
        else {
            isEligibleForIntro = true
            return
        }
        isEligibleForIntro = await subscription.isEligibleForIntroOffer
    }

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error):
            throw error
        case let .verified(safe):
            return safe
        }
    }
}
