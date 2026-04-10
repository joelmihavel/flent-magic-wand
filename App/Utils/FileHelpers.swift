import Foundation
import UniformTypeIdentifiers

enum FileHelpers {
    /// Supported image types for import.
    static let supportedTypes: [UTType] = [.png, .jpeg, .webP, .heic, .tiff, .bmp]

    /// Check if a URL points to a supported image.
    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains(where: { type.conforms(to: $0) })
    }

    /// Human-readable file size.
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Create a unique temp directory for a processing session.
    static func createSessionDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgremover_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Clean up a session directory.
    static func cleanupSession(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
