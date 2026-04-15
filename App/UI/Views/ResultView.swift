import SwiftUI
import UniformTypeIdentifiers

/// Shows the processed result(s). Handles single and batch modes, offers
/// Back (to action selection), Process Another (new upload), and Save.
struct ResultView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.results.count > 1 {
            BatchResultView()
        } else {
            SingleResultView()
        }
    }
}

// MARK: - Single Result

private struct SingleResultView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 12) {
            if let result = appState.primaryResult {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        let displayImage = showOriginal ? result.originalImage : result.processedImage

                        if !showOriginal && result.outputFormat == .png {
                            CheckerboardBackground()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Image(nsImage: displayImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    DismissImageButton {
                        withAnimation(.smooth(duration: 0.35)) {
                            appState.reset()
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 260)
                .padding(.horizontal, 20)

                if result.outputFormat == .png {
                    BeforeAfterToggle(showOriginal: $showOriginal)
                        .padding(.horizontal, 20)
                } else {
                    CompressionStats(result: result)
                        .padding(.horizontal, 20)
                }

                Button(action: saveImage) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                        Text("Save")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    BackButton {
                        withAnimation(.smooth(duration: 0.3)) {
                            appState.backToActionChoice()
                        }
                    }

                    ProcessAnotherButton {
                        pickNewFiles()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func saveImage() {
        guard let result = appState.primaryResult else { return }
        let format = result.outputFormat

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(result.sourceName).\(format.fileExtension)"
        panel.message = "Save your processed image"

        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != format.fileExtension {
            url = url.appendingPathExtension(format.fileExtension)
        }

        do {
            try appState.saveResult(result, to: url)
        } catch {
            appState.phase = .failed(message: error.localizedDescription)
        }
    }

    private func pickNewFiles() {
        pickFiles(appState: appState)
    }
}

// MARK: - Batch Result

private struct BatchResultView: View {
    @EnvironmentObject var appState: AppState

    private var totalOriginal: Int64 { appState.results.reduce(0) { $0 + $1.originalFileSize } }
    private var totalProcessed: Int64 { appState.results.reduce(0) { $0 + $1.processedFileSize } }
    private var ratio: Double {
        guard totalProcessed > 0, totalOriginal > 0 else { return 0 }
        return Double(totalOriginal) / Double(totalProcessed)
    }
    private var format: OutputFormat { appState.results.first?.outputFormat ?? .png }

    var body: some View {
        VStack(spacing: 12) {
            // Thumbnail grid — up to 8 shown
            let cols = [GridItem(.adaptive(minimum: 62, maximum: 80), spacing: 6)]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(appState.results.prefix(8))) { result in
                    Image(nsImage: result.processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                if appState.results.count > 8 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.5))
                        Text("+\(appState.results.count - 8)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
                }
            }
            .padding(.horizontal, 20)

            // Aggregate stats
            HStack(spacing: 10) {
                StatBadge(icon: "photo.stack", label: "\(appState.results.count) images")
                StatBadge(icon: "doc", label: formatBytes(totalOriginal))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                StatBadge(icon: "doc.fill", label: "\(formatBytes(totalProcessed)) (\(format.displayName))")
                Spacer(minLength: 0)
                if ratio > 0 {
                    Text(String(format: "%.1fx smaller", ratio))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)

            // Save All
            Button(action: saveAll) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                    Text("Save All")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            // Back + Process Another
            HStack(spacing: 10) {
                BackButton {
                    withAnimation(.smooth(duration: 0.3)) {
                        appState.backToActionChoice()
                    }
                }
                ProcessAnotherButton {
                    pickFiles(appState: appState)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func saveAll() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick a folder to save all \(appState.results.count) images"
        panel.prompt = "Save Here"
        panel.level = .floating

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            try appState.saveAllResults(to: folder)
        } catch {
            appState.phase = .failed(message: error.localizedDescription)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Shared Buttons

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(.quaternary.opacity(0.4))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ProcessAnotherButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Process Another")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(.quaternary.opacity(0.4))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Picker helper

@MainActor
private func pickFiles(appState: AppState) {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.message = "Select one or more images"
    panel.level = .floating

    panel.begin { response in
        guard response == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { @MainActor in
            appState.handleFileURLs(urls)
        }
    }
}

// MARK: - Before/After Toggle

struct BeforeAfterToggle: View {
    @Binding var showOriginal: Bool

    var body: some View {
        HStack(spacing: 0) {
            ToggleSegment(title: "Result", isActive: !showOriginal) {
                showOriginal = false
            }
            ToggleSegment(title: "Original", isActive: showOriginal) {
                showOriginal = true
            }
        }
        .frame(height: 32)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ToggleSegment: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
            }
        }) {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compression Stats (single)

struct CompressionStats: View {
    let result: ProcessingResult

    private var originalLabel: String { formatBytes(result.originalFileSize) }
    private var compressedLabel: String { formatBytes(result.processedFileSize) }
    private var ratioLabel: String {
        guard result.originalFileSize > 0 else { return "—" }
        let ratio = Double(result.originalFileSize) / Double(max(result.processedFileSize, 1))
        return String(format: "%.1fx smaller", ratio)
    }

    var body: some View {
        HStack(spacing: 10) {
            StatBadge(icon: "doc", label: originalLabel)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            StatBadge(icon: "doc.fill", label: "\(compressedLabel) (\(result.outputFormat.displayName))")
            Spacer(minLength: 0)
            Text(ratioLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3))
        .clipShape(Capsule())
    }
}
