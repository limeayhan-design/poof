import Combine
import Contacts
import SwiftUI

// Provider cross-platform de la photo de profil de l'utilisateur — récupérée
// depuis la Me Card de Contacts (source la plus fiable pour l'iCloud profile
// photo, disponible sur iOS et macOS avec l'accès Contacts).

@MainActor
final class PoofProfileImage: ObservableObject {
    static let shared = PoofProfileImage()

    @Published private(set) var image: PoofImage?
    @Published var displayName: String = UserDefaults.standard.string(forKey: Keys.name) ?? "" {
        didSet {
            UserDefaults.standard.set(displayName, forKey: Keys.name)
            onLocalChange?()
        }
    }

    /// Callback branché par `PoofSession` — appelé à chaque mutation locale
    /// de l'avatar ou du displayName pour trigger le push aux autres devices
    /// du même compte iCloud (sync cross-device).
    var onLocalChange: (() -> Void)?

    @Published private(set) var appleUserId: String? = UserDefaults.standard.string(forKey: Keys.appleUserId)
    @Published private(set) var appleEmail: String? = UserDefaults.standard.string(forKey: Keys.appleEmail)

    var isSignedIn: Bool {
        appleUserId != nil
    }

    private enum Keys {
        static let name = "poof.account.name"
        static let imageFile = "poof.account.avatar.png"
        static let appleUserId = "poof.account.appleUserId"
        static let appleEmail = "poof.account.appleEmail"
    }

    /// Persiste les infos reçues de Sign in with Apple. Le nom écrase le
    /// displayName seulement s'il est non vide (Apple ne renvoie le nom
    /// qu'au 1er login).
    func applyAppleSignIn(userId: String, fullName: String?, email: String?) {
        appleUserId = userId
        UserDefaults.standard.set(userId, forKey: Keys.appleUserId)
        if let email {
            appleEmail = email
            UserDefaults.standard.set(email, forKey: Keys.appleEmail)
        }
        if let fullName, !fullName.isEmpty {
            displayName = fullName
        }
        // Nouvelle identité de compte → trigger le push pour que ce socket
        // soit taggé côté serveur avec le bon appleUserId.
        onLocalChange?()
    }

    /// Déconnexion locale — Apple ne fournit pas d'API "sign out" (le lien
    /// reste dans Réglages iCloud → Apps utilisant Apple ID). On efface juste
    /// nos données locales.
    func signOutApple() {
        appleUserId = nil
        appleEmail = nil
        UserDefaults.standard.removeObject(forKey: Keys.appleUserId)
        UserDefaults.standard.removeObject(forKey: Keys.appleEmail)
    }

    private var didLoad = false

    private init() {
        // Charge tout de suite l'avatar custom persisté (path Documents).
        if let img = loadCustomImage() {
            image = img
        }
    }

    /// À appeler au démarrage du composant qui affiche la photo. Idempotent —
    /// n'exécute le fetch qu'une fois par lancement (l'image ne change pas
    /// souvent). Fallback Me Card si aucun avatar custom.
    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard image == nil else { return }
        Task { await fetch() }
    }

    /// Persiste une nouvelle photo de profil choisie par l'utilisateur.
    func setCustomImage(_ img: PoofImage?) {
        image = img
        if let img, let data = img.poofPNGData {
            try? data.write(to: customImageURL())
        } else {
            try? FileManager.default.removeItem(at: customImageURL())
        }
        onLocalChange?()
    }

    /// Applique un avatar + displayName reçu par sync signaling depuis un
    /// autre device du même compte iCloud (identifié par `appleUserId`).
    /// Décode le JPEG base64 et met à jour l'image + name affichés
    /// partout (nuage top-right, account view, support chat).
    func applyRemoteSync(avatarBase64: String?, displayName: String?) {
        if let displayName, !displayName.isEmpty, displayName != self.displayName {
            // Sync par-dessus le UserDefaults sans re-triggerer le push
            // remote (évite la boucle infinie A pousse → B applique →
            // B pousse → A applique). On modifie via UserDefaults direct.
            UserDefaults.standard.set(displayName, forKey: Keys.name)
            self.displayName = displayName
        }
        guard let avatarBase64,
              let data = Data(base64Encoded: avatarBase64),
              let img = PoofImage(data: data) else { return }
        // Persiste comme si c'était une custom image — le device la garde
        // même hors ligne. On ne re-push pas (silent update via didLoad).
        image = img
        if let png = img.poofPNGData {
            try? png.write(to: customImageURL())
        }
    }

    private func loadCustomImage() -> PoofImage? {
        let url = customImageURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return PoofImage(data: data)
    }

    private func customImageURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(Keys.imageFile)
    }

    private func fetch() async {
        #if os(macOS)
            // macOS : API Me Card native disponible via CNContactStore.
            let store = CNContactStore()
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .notDetermined {
                let granted = await (try? store.requestAccess(for: .contacts)) ?? false
                guard granted else { return }
            } else if status != .authorized {
                return
            }
            let keys: [CNKeyDescriptor] = [
                CNContactImageDataKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else { return }
            let data = me.imageData ?? me.thumbnailImageData
            guard let data, let img = PoofImage(data: data) else { return }
            image = img
            // Persiste + trigger le push aux autres devices du même compte
            // iCloud — l'iPhone (où l'API Me Card est bloquée par Apple)
            // reçoit ainsi la photo automatiquement via sync signaling.
            if let png = img.poofPNGData {
                try? png.write(to: customImageURL())
            }
            onLocalChange?()
        #else
            // iOS : `unifiedMeContactWithKeys` a été retirée par Apple pour
            // raisons privacy. Fallback nil → le nuage affiche le stroke vide.
            // Alternative future : ASAuthorizationAppleIDProvider pour récupérer
            // le user profile via Sign in with Apple.
            return
        #endif
    }
}
