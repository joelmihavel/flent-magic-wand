import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Encodes NSImages to modern compressed formats (WebP, AVIF) using Apple's
/// native ImageIO. AVIF is hardware-accelerated on Apple silicon (macOS 13+),
/// WebP encode is supported on macOS 14+. Both use a tunable lossy quality
/// parameter — 0.75 yields visually-lossless output with ~10x size reduction
/// for typical photographs.
enum ImageConverter {
    /// Encode via Pillow (libwebp / libavif) for best quality + compression.
    /// When a source URL is available we pass it through untouched so the
    /// encoder preserves the embedded ICC color profile and EXIF data —
    /// this is what fixes the washed-out / "lighter than original" look
    /// that occurs when reconstructing the image from an NSImage bitmap.
    /// - Parameters:
    ///   - image: Source image (used only as a fallback when sourceURL is nil).
    ///   - sourceURL: Original file URL, if available.
    ///   - format: Target output format (.webp or .avif).
    ///   - quality: 0–100. 85 is the sweet spot for visually-lossless output.
    static func encodeViaPillow(
        image: NSImage,
        sourceURL: URL?,
        format: OutputFormat,
        quality: Int = 85,
        targetKB: Int = 0
    ) async throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("mw_convert_out_\(UUID().uuidString).\(format.fileExtension)")

        // Prefer the original file so ICC/EXIF are preserved; otherwise
        // write the NSImage to a lossless temp PNG first.
        let inputURL: URL
        let inputIsTemporary: Bool
        if let source = sourceURL, FileManager.default.fileExists(atPath: source.path) {
            inputURL = source
            inputIsTemporary = false
        } else {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw ImageConversionError.encodingFailed
            }
            let tempInput = tempDir.appendingPathComponent("mw_convert_in_\(UUID().uuidString).png")
            try pngData.write(to: tempInput)
            inputURL = tempInput
            inputIsTemporary = true
        }

        defer {
            if inputIsTemporary { try? FileManager.default.removeItem(at: inputURL) }
            try? FileManager.default.removeItem(at: outputURL)
        }

        let bridge = PythonBridge()
        try await bridge.runImageConversion(
            input: inputURL,
            output: outputURL,
            format: format.fileExtension,
            quality: quality,
            targetKB: targetKB
        )

        return try Data(contentsOf: outputURL)
    }

    /// Legacy native-ImageIO encoder (kept for PNG + potential future use).
    static func encode(_ image: NSImage, format: OutputFormat, quality: CGFloat = 0.75) throws -> Data {
        if format == .png {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [.interlaced: false]) else {
                throw ImageConversionError.encodingFailed
            }
            return data
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageConversionError.encodingFailed
        }

        let typeID = format.contentType.identifier as CFString
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(mutableData, typeID, 1, nil) else {
            throw ImageConversionError.formatUnsupported(format.displayName)
        }

        let clamped = max(0.0, min(1.0, quality))
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: clamped
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageConversionError.formatUnsupported(format.displayName)
        }

        return mutableData as Data
    }
}

enum ImageConversionError: LocalizedError {
    case encodingFailed
    case formatUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the source image."
        case .formatUnsupported(let name):
            return "\(name) encoding isn't available on this macOS version."
        }
    }
}
