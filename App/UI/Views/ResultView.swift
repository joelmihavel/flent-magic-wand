import SwiftUI

/// Shows the processed result with before/after comparison, lasso refinement, and download.
struct ResultView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOriginal = false
    @State private var lassoActive = false
    @State private var isRefining = false

    var body: some View {
        VStack(spacing: 12) {
            if let result = appState.result {
                // Image Display with dismiss button + optional lasso overlay
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        let displayImage = showOriginal ? result.originalImage : result.processedImage

                        // Checkerboard background for transparency
                        if !showOriginal {
                            CheckerboardBackground()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Image(nsImage: displayImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                if lassoActive {
                                    LassoOverlay(isActive: $lassoActive) { points in
                                        handleLassoComplete(points)
                                    }
                                }
                            }
                            .overlay {
                                if isRefining {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.black.opacity(0.3))
                                        VStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Refining...")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                            }
                    }

                    // X button to clear and start over
                    if !lassoActive {
                        DismissImageButton {
                            withAnimation(.smooth(duration: 0.35)) {
                                appState.reset()
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(maxHeight: 260)
                .padding(.horizontal, 20)

                // Before / After Toggle
                BeforeAfterToggle(showOriginal: $showOriginal)
                    .padding(.horizontal, 20)

                // Action buttons
                HStack(spacing: 10) {
                    // Refine button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            lassoActive.toggle()
                            showOriginal = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: lassoActive ? "xmark" : "lasso")
                                .font(.system(size: 13, weight: .medium))
                            Text(lassoActive ? "Cancel" : "Refine")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(lassoActive ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.quaternary))
                        .foregroundStyle(lassoActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefining)

                    // Save button
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
                    .disabled(isRefining || lassoActive)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Lasso Refinement

    private func handleLassoComplete(_ points: [[Double]]) {
        guard !isRefining, let result = appState.result else { return }

        isRefining = true
        Task {
            do {
                let refined = try await appState.refinWithLasso(
                    originalImage: result.originalImage,
                    lassoPoints: points
                )
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.3)) {
                        appState.updateResult(processedImage: refined)
                        isRefining = false
                    }
                }
            } catch {
                await MainActor.run {
                    isRefining = false
                    appState.phase = .failed(message: "Refinement failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Save

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "magic-wand-output.png"
        panel.message = "Save your processed image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try appState.saveResult(to: url)
        } catch {
            appState.phase = .failed(message: error.localizedDescription)
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
