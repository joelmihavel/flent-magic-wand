import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Encodes NSImages to WebP/AVIF with a size budget.
///
/// - **AVIF** uses ImageIO natively (macOS 13+, hardware-accelerated on Apple
///   silicon). When a source file URL is available we read bytes through
///   `CGImageSource` and hand the source directly to the destination, which
///   preserves the embedded ICC color profile and EXIF orientation.
/// - **WebP** shells out to `cwebp` (libwebp CLI). Apple's ImageIO doesn't
///   reliably offer WebP encode, and `cwebp` is the reference encoder with
///   the best quality/size tradeoff. The build script bundles the binary
///   inside the .app; in dev we fall back to `/opt/homebrew/bin/cwebp`.
///
/// Both paths binary-search the highest quality that fits within a given
/// byte budget, progressively downscaling if even minimum quality at the
/// source resolution is too large.
enum ImageConverter {
    // MARK: - Public API

    /// Encode `image` into `format`. If `targetKB > 0`, the output is
    /// size-budgeted (in decimal kilobytes).
    static func encode(
        image: NSImage,
        sourceURL: URL?,
        format: OutputFormat,
        quality: Int = 85,
        targetKB: Int = 0
    ) async throws -> Data {
        let budgetBytes = targetKB > 0 ? targetKB * 1000 : 0

        switch format {
        case .webp:
            return try await encodeWebP(image: image, sourceURL: sourceURL, quality: quality, budgetBytes: budgetBytes)
        case .avif:
            return try encodeAVIF(image: image, sourceURL: sourceURL, quality: quality, budgetBytes: budgetBytes)
        case .png:
            guard let data = compressToPNG(image: image) else {
                throw ImageConversionError.encodingFailed
            }
            return data
        }
    }

    // MARK: - WebP via cwebp

    private static func encodeWebP(image: NSImage, sourceURL: URL?, quality: Int, budgetBytes: Int) async throws -> Data {
        guard let cwebpPath = locateCwebp() else {
            throw ImageConversionError.cwebpMissing
        }

        // cwebp reads common formats directly (PNG, JPG, TIFF, WebP). If we
        // have a source URL, use it. Otherwise, write the NSImage to a temp
        // PNG so cwebp can read it.
        let (inputURL, inputIsTemp) = try materializeInput(image: image, sourceURL: sourceURL)
        defer {
            if inputIsTemp { try? FileManager.default.removeItem(at: inputURL) }
        }

        if budgetBytes == 0 {
            return try runCwebp(binary: cwebpPath, input: inputURL, quality: quality, resizeTo: nil)
        }

        // Stage 1: binary-search quality at source resolution
        if let data = try bestCwebpWithin(binary: cwebpPath, input: inputURL, budget: budgetBytes, resizeTo: nil, qLo: 20, qHi: 95) {
            return data
        }

        // Stage 2: progressively downscale
        guard let baseSize = imageDimensions(url: inputURL) else {
            // Give up gracefully at minimum quality
            return try runCwebp(binary: cwebpPath, input: inputURL, quality: 20, resizeTo: nil)
        }

        for pct in [0.85, 0.70, 0.55, 0.40, 0.30, 0.20] {
            let w = max(32, Int(Double(baseSize.width) * pct))
            let h = max(32, Int(Double(baseSize.height) * pct))
            if let data = try bestCwebpWithin(binary: cwebpPath, input: inputURL, budget: budgetBytes, resizeTo: (w, h), qLo: 20, qHi: 90) {
                return data
            }
        }

        // Last resort: tiny + low quality
        let tinyW = max(32, Int(Double(baseSize.width) * 0.15))
        let tinyH = max(32, Int(Double(baseSize.height) * 0.15))
        return try runCwebp(binary: cwebpPath, input: inputURL, quality: 10, resizeTo: (tinyW, tinyH))
    }

    private static func bestCwebpWithin(binary: URL, input: URL, budget: Int, resizeTo: (Int, Int)?, qLo: Int, qHi: Int) throws -> Data? {
        let floor = try runCwebp(binary: binary, input: input, quality: qLo, resizeTo: resizeTo)
        if floor.count > budget { return nil }

        var best = floor
        var lo = qLo
        var hi = qHi
        while lo <= hi {
            let mid = (lo + hi) / 2
            let data = try runCwebp(binary: binary, input: input, quality: mid, resizeTo: resizeTo)
            if data.count <= budget {
                best = data
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private static func runCwebp(binary: URL, input: URL, quality: Int, resizeTo: (Int, Int)?) throws -> Data {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw_webp_\(UUID().uuidString).webp")
        defer { try? FileManager.default.removeItem(at: output) }

        var args: [String] = [
            "-quiet",
            "-q", String(max(0, min(100, quality))),
            "-m", "6",               // slowest / best compression
            "-metadata", "icc",      // preserve color profile
        ]
        if let (w, h) = resizeTo {
            args.append(contentsOf: ["-resize", String(w), String(h)])
        }
        args.append(contentsOf: ["-o", output.path, input.path])

        let process = Process()
        process.executableURL = binary
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImageConversionError.cwebpFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return try Data(contentsOf: output)
    }

    private static func locateCwebp() -> URL? {
        // 1) Bundled inside the .app
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/cwebp"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        // 2) Homebrew on Apple silicon / Intel
        for path in ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // 3) $PATH
        if let env = ProcessInfo.processInfo.environment["PATH"] {
            for dir in env.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("cwebp")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    // MARK: - AVIF via ImageIO

    private static func encodeAVIF(image: NSImage, sourceURL: URL?, quality: Int, budgetBytes: Int) throws -> Data {
        let typeID = "public.avif" as CFString

        if budgetBytes == 0 {
            return try avifEncode(image: image, sourceURL: sourceURL, typeID: typeID, quality: quality, scale: 1.0)
        }

        // Stage 1: search at source resolution
        if let data = try bestAVIFWithin(image: image, sourceURL: sourceURL, typeID: typeID, budget: budgetBytes, scale: 1.0, qLo: 20, qHi: 95) {
            return data
        }

        // Stage 2: downscale
        for pct in [0.85, 0.70, 0.55, 0.40, 0.30, 0.20] {
            if let data = try bestAVIFWithin(image: image, sourceURL: sourceURL, typeID: typeID, budget: budgetBytes, scale: pct, qLo: 20, qHi: 90) {
                return data
            }
        }

        // Last resort
        return try avifEncode(image: image, sourceURL: sourceURL, typeID: typeID, quality: 10, scale: 0.15)
    }

    private static func bestAVIFWithin(image: NSImage, sourceURL: URL?, typeID: CFString, budget: Int, scale: Double, qLo: Int, qHi: Int) throws -> Data? {
        let floor = try avifEncode(image: image, sourceURL: sourceURL, typeID: typeID, quality: qLo, scale: scale)
        if floor.count > budget { return nil }

        var best = floor
        var lo = qLo
        var hi = qHi
        while lo <= hi {
            let mid = (lo + hi) / 2
            let data = try avifEncode(image: image, sourceURL: sourceURL, typeID: typeID, quality: mid, scale: scale)
            if data.count <= budget {
                best = data
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private static func avifEncode(image: NSImage, sourceURL: URL?, typeID: CFString, quality: Int, scale: Double) throws -> Data {
        // Resolve source CGImage + size.
        // When we have a URL we go through CGImageSource so ICC/EXIF survive.
        let (cgSource, sourceSize): (CGImage, CGSize)
        if let url = sourceURL,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            cgSource = cg
            sourceSize = CGSize(width: cg.width, height: cg.height)
        } else {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ImageConversionError.encodingFailed
            }
            cgSource = cg
            sourceSize = CGSize(width: cg.width, height: cg.height)
        }

        // Apply downscale if requested.
        let targetW = max(32, Int(round(sourceSize.width * scale)))
        let targetH = max(32, Int(round(sourceSize.height * scale)))
        let finalImage: CGImage
        if scale < 0.999 {
            guard let scaled = resize(cgImage: cgSource, to: CGSize(width: targetW, height: targetH)) else {
                throw ImageConversionError.encodingFailed
            }
            finalImage = scaled
        } else {
            finalImage = cgSource
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, typeID, 1, nil) else {
            throw ImageConversionError.formatUnsupported("AVIF")
        }

        let q = CGFloat(max(0, min(100, quality))) / 100.0
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: q
        ]
        CGImageDestinationAddImage(dest, finalImage, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw ImageConversionError.formatUnsupported("AVIF")
        }
        return data as Data
    }

    private static func resize(cgImage: CGImage, to size: CGSize) -> CGImage? {
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = cgImage.bitmapInfo.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func materializeInput(image: NSImage, sourceURL: URL?) throws -> (URL, Bool) {
        if let url = sourceURL, FileManager.default.fileExists(atPath: url.path) {
            return (url, false)
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageConversionError.encodingFailed
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw_in_\(UUID().uuidString).png")
        try pngData.write(to: temp)
        return (temp, true)
    }

    private static func imageDimensions(url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (w, h)
    }

    static func compressToPNG(image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [.interlaced: false])
    }
}

enum ImageConversionError: LocalizedError {
    case encodingFailed
    case formatUnsupported(String)
    case cwebpMissing
    case cwebpFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the source image."
        case .formatUnsupported(let name):
            return "\(name) encoding isn't available on this macOS version."
        case .cwebpMissing:
            return "WebP encoder (cwebp) not found. For dev, run 'brew install webp'."
        case .cwebpFailed(let detail):
            return "WebP encoding failed: \(detail)"
        }
    }
}
