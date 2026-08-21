import CoreGraphics
import Foundation

/// Contrat Studio — les vidéos sont pré-encodées côté sender pour matcher
/// la plateforme cible avant l'envoi. Le destinataire reçoit un fichier
/// upload-ready (spec Insta/TikTok/Shorts respectée), pas de recompression
/// destructrice par les serveurs sociaux.
struct StudioConfig: Equatable, Codable {
    var platform: StudioPlatform
    /// Applique un filigrane texte (logo, handle) en overlay avant l'encode.
    /// Nécessite `applyWatermark == true`, sinon ignoré.
    var applyWatermark: Bool
    var watermarkText: String

    /// Preset appliqué au 1er tap sur le chip Studio — Instagram Reels étant
    /// la plateforme la plus consommée pour du vertical short-form.
    static let defaults = StudioConfig(
        platform: .instagramReels, applyWatermark: false, watermarkText: ""
    )
}

/// Plateformes cibles supportées. Chaque case porte ses spécifications
/// techniques (résolution, aspect, bitrate cible, format).
enum StudioPlatform: String, Equatable, Codable, CaseIterable, Identifiable {
    case instagramReels
    case tiktok
    case youtubeShorts
    case linkedin
    case masterPassthrough

    var id: String {
        rawValue
    }

    /// SF Symbol utilisée dans le picker sheet.
    var icon: String {
        switch self {
        case .instagramReels: "camera.macro"
        case .tiktok: "music.note.list"
        case .youtubeShorts: "play.rectangle.fill"
        case .linkedin: "briefcase.fill"
        case .masterPassthrough: "square.stack.3d.up.fill"
        }
    }

    var label: L10n {
        switch self {
        case .instagramReels: L10n(fr: "Instagram Reels", en: "Instagram Reels")
        case .tiktok: L10n(fr: "TikTok", en: "TikTok")
        case .youtubeShorts: L10n(fr: "YouTube Shorts", en: "YouTube Shorts")
        case .linkedin: L10n(fr: "LinkedIn", en: "LinkedIn")
        case .masterPassthrough: L10n(fr: "Master (sans réencode)", en: "Master (no re-encode)")
        }
    }

    var subtitle: L10n {
        switch self {
        case .instagramReels: L10n(fr: "1080×1920 vertical, H.264", en: "1080×1920 vertical, H.264")
        case .tiktok: L10n(fr: "1080×1920 vertical, H.264", en: "1080×1920 vertical, H.264")
        case .youtubeShorts: L10n(fr: "1080×1920 vertical, H.264", en: "1080×1920 vertical, H.264")
        case .linkedin: L10n(fr: "1080×1350 vertical 4:5, H.264", en: "1080×1350 vertical 4:5, H.264")
        case .masterPassthrough: L10n(fr: "Codec d'origine préservé", en: "Original codec preserved")
        }
    }

    /// Résolution cible en pixels (pour AVMutableVideoComposition — V2).
    /// En V1 on utilise juste `usesPassthrough` : les 4 plateformes exportent
    /// en H.264+AAC standard, upload-ready sans recompression sociale.
    var renderSize: CGSize {
        switch self {
        case .instagramReels, .tiktok, .youtubeShorts: CGSize(width: 1080, height: 1920)
        case .linkedin: CGSize(width: 1080, height: 1350)
        case .masterPassthrough: .zero
        }
    }

    var usesPassthrough: Bool {
        self == .masterPassthrough
    }
}
