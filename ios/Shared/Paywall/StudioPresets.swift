import Combine
import Foundation
import SwiftUI

/// Preset custom sauvegardé par l'utilisateur — combo StudioConfig + nom.
/// Persisté en JSON dans UserDefaults, rappelable en 1 tap dans la sheet.
struct StudioPreset: Identifiable, Equatable, Codable {
    var id: UUID = .init()
    var name: String
    var config: StudioConfig
}

/// Store singleton pour les presets Studio. Persiste dans UserDefaults sous
/// une clé unique — pas de backend, pas de sync iCloud (V1 local only).
@MainActor
final class StudioPresetStore: ObservableObject {
    static let shared = StudioPresetStore()

    private static let storageKey = "poof.studio.presets"

    @Published var presets: [StudioPreset] = []

    private init() {
        load()
    }

    func save(_ preset: StudioPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        persist()
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([StudioPreset].self, from: data)
        else { return }
        presets = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
