import SwiftUI
import UniformTypeIdentifiers

/// Idle state: drag & drop zone + upload button.
struct IdleView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragHovering = false

    var body: some View {
        VStack(spacing: 20) {
            // Drop Zone
            DropZoneView(isDragHovering: $isDragHovering)
                .onDrop(of: [.image, .fileURL], isTargeted: $isDragHovering) { providers in
                    handleDrop(providers)
                    return true
                }

            // Upload Button
            Button(action: pickFile) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 13, weight: .medium))
                    Text("Choose Image")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 10))

            // Supported formats hint
            Text("PNG, JPG, WEBP, HEIC")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - File Picker

    private func pickFile() {
        // Temporarily activate the app so NSOpenPanel can become key
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an image to remove its background"
        panel.level = .floating

        panel.begin { [weak appState] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                appState?.handleFileURL(url)
            }
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        // Try loading as file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    appState.handleFileURL(url)
                }
            }
            return
        }

        // Fallback: load as image data
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let url = item as? URL {
                    Task { @MainActor in
                        appState.handleFileURL(url)
                    }
                } else if let data = item as? Data, let image = NSImage(data: data) {
                    Task { @MainActor in
                        appState.handleImageDrop(image)
                    }
                }
            }
        }
    }
}
