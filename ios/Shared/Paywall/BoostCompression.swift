import Compression
import Foundation

/// Compression LZFSE Apple sans perte — utilisée quand `BoostConfig.compression`
/// est actif. LZFSE est optimisé pour l'efficacité énergétique iOS/macOS
/// (débit + ratio équilibrés). Gain typique : 20-40 % sur fichiers texte /
/// documents ; ~0 % sur médias déjà compressés (jpg, mp4). On applique de
/// toute façon — no-op si sans gain, jamais destructif.
enum BoostCompression {
    enum CompressError: Error {
        case emptyInput
        case compressionFailed
        case decompressionFailed
    }

    /// Compresse le fichier source, écrit le résultat dans un fichier
    /// temporaire séparé. Retourne l'URL du compressé (avec suffixe .lzfse).
    /// Le fichier source reste intact.
    static func compressFile(at source: URL) throws -> URL {
        let sourceData = try Data(contentsOf: source)
        guard !sourceData.isEmpty else { throw CompressError.emptyInput }
        let compressed = try compress(sourceData)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoofBoost", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent + ".lzfse")
        try? FileManager.default.removeItem(at: dest)
        try compressed.write(to: dest)
        return dest
    }

    /// Décompresse en place — remplace le contenu du fichier chiffré par le
    /// clair. Utilisé côté receiver quand `meta.boostConfig?.compression == true`.
    static func decompressInPlace(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let plain = try decompress(data)
        try plain.write(to: url)
    }

    // MARK: - Low-level compression

    private static func compress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { srcBuffer -> Data in
            let srcPtr = srcBuffer.bindMemory(to: UInt8.self).baseAddress!
            // On alloue le double de la source — pire cas LZFSE légèrement
            // plus grand que la source pour données incompressibles.
            let dstCapacity = max(data.count * 2, 128)
            let dstPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
            defer { dstPtr.deallocate() }
            let compressedSize = compression_encode_buffer(
                dstPtr, dstCapacity,
                srcPtr, data.count,
                nil,
                COMPRESSION_LZFSE
            )
            guard compressedSize > 0 else { throw CompressError.compressionFailed }
            return Data(bytes: dstPtr, count: compressedSize)
        }
    }

    private static func decompress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { srcBuffer -> Data in
            let srcPtr = srcBuffer.bindMemory(to: UInt8.self).baseAddress!
            // Facteur d'expansion : LZFSE peut donner du 5-10× l'input. On
            // alloue large — l'excédent est libéré à la fin de la Data init.
            let dstCapacity = max(data.count * 10, 4096)
            let dstPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
            defer { dstPtr.deallocate() }
            let decompressedSize = compression_decode_buffer(
                dstPtr, dstCapacity,
                srcPtr, data.count,
                nil,
                COMPRESSION_LZFSE
            )
            guard decompressedSize > 0 else { throw CompressError.decompressionFailed }
            return Data(bytes: dstPtr, count: decompressedSize)
        }
    }
}
