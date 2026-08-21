import Foundation

// Live Activity / Dynamic Island désactivés — Uras 2026-08-18. Les stubs
// no-op sont conservés pour ne pas casser les ~15 call sites dans PoofSession
// et PoofSendView (startSend/updateSend/endSend/startReceive/updateReceive/
// endReceive/endAllOrphans). Toutes les méthodes ne font rien → aucun DI
// ne s'affiche, aucune Live Activity n'est requêtée à ActivityKit.
//
// Pour réactiver plus tard : restaurer la version ActivityKit depuis git
// (dernière version fonctionnelle avant ce commit) + remettre les keys
// NSSupportsLiveActivities dans Poof-Info.plist.

@MainActor
final class PoofLiveActivityController {
    static let shared = PoofLiveActivityController()
    private init() {}

    func startSend(id _: String, name _: String, total _: UInt64, peerName _: String) {}
    func startReceive(id _: String, name _: String, total _: UInt64, peerName _: String) {}
    func updateSend(id _: String, bytes _: UInt64) {}
    func updateReceive(id _: String, bytes _: UInt64) {}
    func endSend(id _: String, success _: Bool) {}
    func endReceive(id _: String, success _: Bool) {}
    func endAllOrphans() {}
}
