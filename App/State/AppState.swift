import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Output Format

enum OutputFormat: Equatable {
    case png
    case webp
    case avif

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .webp: return .webP
        case .avif: return UTType("public.avif") ?? .image
        }
    }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        }
    }
}

// MARK: - Processing Action

enum ProcessingAction: Equatable, Identifiable, CaseIterable {
    case removeBackground
    case convertWebP
    case convertAVIF

    var id: String {
        switch self {
        case .removeBackground: return "removeBackground"
        case .convertWebP: return "convertWebP"
        case .convertAVIF: return "convertAVIF"
        }
    }

    var title: String {
        switch self {
        case .removeBackground: return "Remove Background"
        case .convertWebP: return "Compress to WebP"
        case .convertAVIF: return "Compress to AVIF"
        }
    }

    var subtitle: String {
        switch self {
        case .removeBackground: return "Cut out the subject, transparent PNG"
        case .convertWebP: return "Smaller files, broad browser support"
        case .convertAVIF: return "Best compression, modern browsers"
        }
    }

    var icon: String {
        switch self {
        case .removeBackground: return "wand.and.stars"
        case .convertWebP: return "arrow.down.circle"
        case .convertAVIF: return "bolt.circle"
        }
    }

    var outputFormat: OutputFormat {
        switch self {
        case .removeBackground: return .png
        case .convertWebP: return .webp
        case .convertAVIF: return .avif
        }
    }
}

// MARK: - Processing State Machine

enum ProcessingPhase: Equatable {
    case idle
    case uploading(progress: Double)
    case awaitingAction
    case processing(action: ProcessingAction, current: Int, total: Int)
    case complete
    case failed(message: String)

    var isProcessing: Bool {
        switch self {
        case .processing, .uploading: return true
        default: return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Drop an image to get started"
        case .uploading(let progress):
            return "Loading image... \(Int(progress * 100))%"
        case .awaitingAction:
            return "Pick what you'd like to do"
        case .processing(let action, let current, let total):
            let base: String
            switch action {
            case .removeBackground: base = "Removing background"
            case .convertWebP: base = "Compressing to WebP"
            case .convertAVIF: base = "Compressing to AVIF"
            }
            return total > 1 ? "\(base) • \(current)/\(total)" : base
        case .complete:
            return "Done!"
        case .failed(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Input Item

struct InputItem: Identifiable, Equatable {
    let id = UUID()
    let image: NSImage
    let sourceURL: URL?
    let fileSize: Int64
    let displayName: String

    static func == (lhs: InputItem, rhs: InputItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Processing Result

struct ProcessingResult: Identifiable {
    let id: UUID
    let originalImage: NSImage
    var processedImage: NSImage
    var outputData: Data
    var outputFormat: OutputFormat
    let originalFileSize: Int64
    var processedFileSize: Int64
    let sourceName: String
    let processingDuration: TimeInterval
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var phase: ProcessingPhase = .idle
    @Published var inputs: [InputItem] = []
    @Published var results: [ProcessingResult] = []
    @Published var isPanelVisible: Bool = false
    @Published var showBeforeImage: Bool = false

    private var processingTask: Task<Void, Never>?

    /// Convenience for views that want the first/only input.
    var primaryInput: InputItem? { inputs.first }
    var primaryResult: ProcessingResult? { results.first }

    // MARK: - Reset / Navigation

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        phase = .idle
        inputs = []
        results = []
        showBeforeImage = false
    }

    /// Return to the action-selection screen, preserving uploaded images.
    /// Cancels any in-flight processing.
    func backToActionChoice() {
        processingTask?.cancel()
        processingTask = nil
        results = []
        showBeforeImage = false
        if inputs.isEmpty {
            phase = .idle
        } else {
            phase = .awaitingAction
        }
    }

    // MARK: - Intake

    func handleImageDrop(_ image: NSImage, fileSize: Int64 = 0) {
        let item = InputItem(
            image: image,
            sourceURL: nil,
            fileSize: fileSize,
            displayName: "image"
        )
        inputs = [item]
        results = []
        phase = .awaitingAction
    }

    func handleFileURL(_ url: URL) {
        handleFileURLs([url])
    }

    func handleFileURLs(_ urls: [URL]) {
        var items: [InputItem] = []
        for url in urls {
            guard let image = NSImage(contentsOf: url) else { continue }
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            items.append(InputItem(
                image: image,
                sourceURL: url,
                fileSize: fileSize,
                displayName: url.deletingPathExtension().lastPathComponent
            ))
        }

        guard !items.isEmpty else {
            phase = .failed(message: "Could not load any images.")
            return
        }

        inputs = items
        results = []
        phase = .awaitingAction
    }

    // MARK: - Processing

    func startAction(_ action: ProcessingAction) {
        guard !inputs.isEmpty else { return }
        processingTask?.cancel()

        let items = inputs
        processingTask = Task { [weak self] in
            guard let self else { return }
            let startTime = Date()
            var collected: [ProcessingResult] = []

            for (index, item) in items.enumerated() {
                if Task.isCancelled { return }
                self.phase = .processing(action: action, current: index + 1, total: items.count)

                do {
                    let result = try await Self.process(item: item, action: action, startTime: Date())
                    if Task.isCancelled { return }
                    collected.append(result)
                    self.results = collected
                } catch is CancellationError {
                    return
                } catch {
                    self.phase = .failed(message: "[\(item.displayName)] \(error.localizedDescription)")
                    return
                }
            }

            _ = startTime
            if Task.isCancelled { return }
            self.phase = .complete
        }
    }

    private static func process(item: InputItem, action: ProcessingAction, startTime: Date) async throws -> ProcessingResult {
        switch action {
        case .removeBackground:
            let processed = try await ImageProcessor.shared.removeBackground(from: item.image)
            let data = compressToPNG(processed) ?? Data()
            return ProcessingResult(
                id: item.id,
                originalImage: item.image,
                processedImage: processed,
                outputData: data,
                outputFormat: .png,
                originalFileSize: item.fileSize,
                processedFileSize: Int64(data.count),
                sourceName: item.displayName,
                processingDuration: Date().timeIntervalSince(startTime)
            )

        case .convertWebP, .convertAVIF:
            let format = action.outputFormat
            let data = try await ImageConverter.encodeViaPillow(
                image: item.image,
                sourceURL: item.sourceURL,
                format: format,
                quality: 85,
                targetKB: 30
            )
            return ProcessingResult(
                id: item.id,
                originalImage: item.image,
                processedImage: item.image,
                outputData: data,
                outputFormat: format,
                originalFileSize: item.fileSize,
                processedFileSize: Int64(data.count),
                sourceName: item.displayName,
                processingDuration: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Lasso Refinement (single-image BG removal only)

    func refinWithLasso(originalImage: NSImage, lassoPoints: [[Double]]) async throws -> NSImage {
        let bridge = PythonBridge()
        let tempDir = FileManager.default.temporaryDirectory

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
        guard var current = results.first else { return }
        current.processedImage = processedImage
        if let compressed = Self.compressToPNG(processedImage) {
            current.outputData = compressed
            current.outputFormat = .png
            current.processedFileSize = Int64(compressed.count)
        }
        results[0] = current
    }

    // MARK: - Save

    /// Save a single result to a specific URL.
    func saveResult(_ result: ProcessingResult, to url: URL) throws {
        guard !result.outputData.isEmpty else {
            throw NSError(domain: "MagicWand", code: 1, userInfo: [NSLocalizedDescriptionKey: "No processed image data"])
        }
        try result.outputData.write(to: url)
    }

    /// Save every result into the given folder using their source names.
    /// Returns the URLs written.
    @discardableResult
    func saveAllResults(to folder: URL) throws -> [URL] {
        var written: [URL] = []
        for result in results {
            var target = folder.appendingPathComponent(result.sourceName)
                .appendingPathExtension(result.outputFormat.fileExtension)

            // Ensure uniqueness if duplicate names exist in the batch.
            var suffix = 1
            while FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(result.sourceName) (\(suffix))")
                    .appendingPathExtension(result.outputFormat.fileExtension)
                suffix += 1
            }

            try result.outputData.write(to: target)
            written.append(target)
        }
        return written
    }

    /// Compress an NSImage to an optimized PNG (lossless).
    static func compressToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [
            .interlaced: false
        ])
    }
}
