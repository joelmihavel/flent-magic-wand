import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Native background removal using Apple's Vision framework.
/// Runs entirely on-device via CoreML / Apple Neural Engine — no Python, no network.
actor ImageProcessor {
    static let shared = ImageProcessor()

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Background Removal (Vision Framework)

    func removeBackground(from image: NSImage) async throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ProcessingError.encodingFailed
        }

        let imageSize = image.size
        let ctx = ciContext

        // Run Vision + CIImage compositing on a background thread
        // so it doesn't block the main thread or actor hop during heavy work.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNGenerateForegroundInstanceMaskRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                    try handler.perform([request])

                    guard let result = request.results?.first else {
                        continuation.resume(throwing: ProcessingError.noForegroundDetected)
                        return
                    }

                    let maskPixelBuffer = try result.generateScaledMaskForImage(
                        forInstances: result.allInstances,
                        from: handler
                    )

                    let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
                    let originalCI = CIImage(cgImage: cgImage)

                    let scaleX = originalCI.extent.width / maskCI.extent.width
                    let scaleY = originalCI.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                    let transparentBackground = CIImage.empty().cropped(to: originalCI.extent)

                    let blended = originalCI.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: transparentBackground,
                        kCIInputMaskImageKey: scaledMask
                    ])

                    guard let outputCG = ctx.createCGImage(blended, from: originalCI.extent) else {
                        continuation.resume(throwing: ProcessingError.outputLoadFailed)
                        return
                    }

                    let outputImage = NSImage(cgImage: outputCG, size: imageSize)
                    continuation.resume(returning: outputImage)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Upscaling (Lanczos)

    func upscale(image: NSImage, scale: Int = 2) async throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ProcessingError.encodingFailed
        }

        let newWidth = cgImage.width * scale
        let newHeight = cgImage.height * scale

        let ciImage = CIImage(cgImage: cgImage)
        let scaleX = CGFloat(scale)
        let scaleY = CGFloat(scale)

        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Apply Lanczos resampling
        let lanczos = scaled.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 1.0,
            kCIInputAspectRatioKey: 1.0
        ])

        guard let outputCG = ciContext.createCGImage(lanczos, from: CGRect(x: 0, y: 0, width: newWidth, height: newHeight)) else {
            throw ProcessingError.outputLoadFailed
        }

        return NSImage(cgImage: outputCG, size: NSSize(width: newWidth, height: newHeight))
    }
}

// MARK: - Errors

enum ProcessingError: LocalizedError {
    case encodingFailed
    case outputLoadFailed
    case noForegroundDetected
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode input image."
        case .outputLoadFailed:
            return "Could not load processed output."
        case .noForegroundDetected:
            return "No foreground subject detected in the image."
        case .processingFailed(let detail):
            return "Processing failed: \(detail)"
        }
    }
}
