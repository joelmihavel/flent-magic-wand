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
            Text("PNG, JPG, WEBP, HEIC — drop or pick multiple for batch")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - File Picker

    private func pickFile() {
        // Temporarily activate the app so NSOpenPanel can become key
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select one or more images"
        panel.level = .floating

        panel.begin { [weak appState] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                appState?.handleFileURLs(urls)
            }
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(_ providers: [NSItemProvider]) {
        // Collect URLs from all providers, then hand the batch to AppState once.
        let group = DispatchGroup()
        var urls: [URL] = []
        var fallbackImage: NSImage?
        let lock = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        lock.lock(); urls.append(url); lock.unlock()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        lock.lock(); urls.append(url); lock.unlock()
                    } else if let data = item as? Data, let image = NSImage(data: data) {
                        lock.lock(); if fallbackImage == nil { fallbackImage = image }; lock.unlock()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                appState.handleFileURLs(urls)
            } else if let image = fallbackImage {
                appState.handleImageDrop(image)
            }
        }
    }
}
