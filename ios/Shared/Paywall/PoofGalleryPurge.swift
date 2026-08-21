import Foundation

#if canImport(Photos)
    import Photos
#endif

/// Helper cross-platform pour supprimer les copies galerie d'un fichier
/// Secure quand son expiry est atteinte. iOS : PHPhotoLibrary ; macOS :
/// no-op (le Save Mac écrit à un chemin utilisateur, hors du scope Poof).
///
/// **iOS** : Apple exige `.readWrite` pour delete + affiche un dialog système
/// « Voulez-vous supprimer ces photos ? » (non-bypassable pour user-owned).
/// Le dialog nécessite l'app au foreground — un delete en background ne
/// s'exécute pas fiablement (pas de UI possible).
enum PoofGalleryPurge {
    static func deleteAssets(
        withLocalIdentifiers identifiers: [String],
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !identifiers.isEmpty else {
            completion?(false)
            return
        }
        #if canImport(Photos) && !os(macOS)
            // Upgrade permission si nécessaire — l'user peut avoir granté
            // .addOnly (avant qu'on demande .readWrite) qui interdit toute
            // suppression. iOS re-prompt si le status ne couvre pas .readWrite.
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                guard status == .authorized || status == .limited else {
                    poofLog("[Poof] Gallery purge — permission refused (\(status.rawValue))")
                    DispatchQueue.main.async { completion?(false) }
                    return
                }
                performDelete(identifiers: identifiers, completion: completion)
            }
        #else
            completion?(false)
        #endif
    }

    #if canImport(Photos) && !os(macOS)
        private static func performDelete(
            identifiers: [String],
            completion: ((Bool) -> Void)?
        ) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var toDelete: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in toDelete.append(asset) }
            poofLog("[Poof] Gallery purge — \(toDelete.count) asset(s) fetched for \(identifiers.count) identifier(s)")
            guard !toDelete.isEmpty else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            } completionHandler: { ok, err in
                poofLog("[Poof] Gallery purge result — ok=\(ok) err=\(String(describing: err))")
                DispatchQueue.main.async { completion?(ok) }
            }
        }
    #endif
}
