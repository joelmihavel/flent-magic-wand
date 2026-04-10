import AppKit
import Foundation

/// Orchestrates multi-step processing pipelines.
/// Designed for extensibility — add new pipeline steps by conforming to `PipelineStep`.
@MainActor
final class PipelineManager: ObservableObject {
    @Published var currentStep: String = ""
    @Published var progress: Double = 0

    private var steps: [PipelineStep] = []

    func configure(steps: [PipelineStep]) {
        self.steps = steps
    }

    func run(inputImage: NSImage) async throws -> NSImage {
        var current = inputImage

        for (index, step) in steps.enumerated() {
            currentStep = step.name
            progress = Double(index) / Double(steps.count)
            current = try await step.process(image: current)
            if Task.isCancelled { throw CancellationError() }
        }

        progress = 1.0
        return current
    }
}

// MARK: - Pipeline Step Protocol

protocol PipelineStep {
    var name: String { get }
    func process(image: NSImage) async throws -> NSImage
}

// MARK: - Built-in Steps

struct BackgroundRemovalStep: PipelineStep {
    let name = "Removing Background"

    func process(image: NSImage) async throws -> NSImage {
        try await ImageProcessor.shared.removeBackground(from: image)
    }
}

struct UpscalingStep: PipelineStep {
    let name = "Upscaling"
    let scale: Int

    init(scale: Int = 2) {
        self.scale = scale
    }

    func process(image: NSImage) async throws -> NSImage {
        try await ImageProcessor.shared.upscale(image: image, scale: scale)
    }
}
