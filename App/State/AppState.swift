import SwiftUI
import Combine

// MARK: - Processing State Machine

enum ProcessingPhase: Equatable {
    case idle
    case uploading(progress: Double)
    case removingBackground
    case upscaling
    case complete
    case failed(message: String)

    var isProcessing: Bool {
        switch self {
        case .removingBackground, .upscaling, .uploading:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Drop an image to get started"
        case .uploading(let progress):
            return "Loading image... \(Int(progress * 100))%"
        case .removingBackground:
            return "Removing background"
        case .upscaling:
            return "Enhancing image"
        case .complete:
            return "Done!"
        case .failed(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Processing Result

struct ProcessingResult: Identifiable {
    let id = UUID()
    let originalImage: NSImage
    var processedImage: NSImage
    var compressedPNGData: Data
    let upscaledImage: NSImage?
    let originalFileSize: Int64
    var processedFileSize: Int64 // Actual compressed PNG size
    let processingDuration: TimeInterval
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var phase: ProcessingPhase = .idle
    @Published var inputImage: NSImage?
    @Published var result: ProcessingResult?
    @Published var isPanelVisible: Bool = false
    @Published var showBeforeImage: Bool = false

    private var processingTask: Task<Void, Never>?

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        phase = .idle
        inputImage = nil
        result = nil
        showBeforeImage = false
    }

    func handleImageDrop(_ image: NSImage, fileSize: Int64 = 0) {
        inputImage = image
        startProcessing(fileSize: fileSize)
    }

    func handleFileURL(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            phase = .failed(message: "Could not load image from file.")
            return
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        inputImage = image
        startProcessing(fileSize: fileSize)
    }

    private func startProcessing(fileSize: Int64) {
        processingTask?.cancel()
        processingTask = Task {
            let startTime = Date()

            guard let input = inputImage else { return }

            // Background Removal (Vision runs on Neural Engine — doesn't block main thread)
            phase = .removingBackground
            let bgRemoved: NSImage
            do {
                bgRemoved = try await ImageProcessor.shared.removeBackground(from: input)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(message: error.localizedDescription)
                return
            }

            if Task.isCancelled { return }

            // Compress to optimized PNG
            let compressedData = Self.compressToPNG(bgRemoved)
            let processedSize = Int64(compressedData?.count ?? 0)

            result = ProcessingResult(
                originalImage: input,
                processedImage: bgRemoved,
                compressedPNGData: compressedData ?? Data(),
                upscaledImage: nil,
                originalFileSize: fileSize,
                processedFileSize: processedSize,
                processingDuration: Date().timeIntervalSince(startTime)
            )
            phase = .complete
        }
    }

    // MARK: - Lasso Refinement

    func refinWithLasso(originalImage: NSImage, lassoPoints: [[Double]]) async throws -> NSImage {
        let bridge = PythonBridge()
        let tempDir = FileManager.default.temporaryDirectory

        // Write original image to temp file
        guard let tiffData = originalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ProcessingError.encodingFailed
        }

        let inputURL = tempDir.appendingPathComponent("mw_lasso_in_\(UUID().uuidString).png")
        let outputURL = tempDir.appendingPathComponent("mw_lasso_out_\(UUID().uuidString).png")

        try pngData.write(to: inputURL)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await bridge.runLassoRefinement(
            input: inputURL,
            output: outputURL,
            lassoPoints: lassoPoints
        )

        guard let outputImage = NSImage(contentsOf: outputURL) else {
            throw ProcessingError.outputLoadFailed
        }

        return outputImage
    }

    func updateResult(processedImage: NSImage) {
        guard var current = result else { return }
        current.processedImage = processedImage
        if let compressed = Self.compressToPNG(processedImage) {
            current.compressedPNGData = compressed
            current.processedFileSize = Int64(compressed.count)
        }
        result = current
    }

    func saveResult(to url: URL) throws {
        guard let data = result?.compressedPNGData, !data.isEmpty else {
            throw NSError(domain: "MagicWand", code: 1, userInfo: [NSLocalizedDescriptionKey: "No processed image data"])
        }
        try data.write(to: url)
    }

    /// Compress an NSImage to an optimized PNG.
    /// Uses maximum PNG compression while preserving full quality (lossless).
    static func compressToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        // PNG is lossless — compressionFactor controls zlib level (higher = smaller file)
        return bitmap.representation(using: .png, properties: [
            .interlaced: false // Non-interlaced is smaller for most images
        ])
    }
}
