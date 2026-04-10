import AppKit
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.b, modifiers: [.command, .shift]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: FloatingPanelController!
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupGlobalShortcut()

        // Pre-create the panel eagerly so first open is instant
        panelController = FloatingPanelController(appState: appState)
        panelController.prewarm()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Magic Wand")?
                .withSymbolConfiguration(config)
            button.image = image
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Global Shortcut

    private func setupGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        if appState.isPanelVisible {
            panelController.hidePanel()
        } else {
            panelController.showPanel(relativeTo: statusItem)
        }
    }
}
