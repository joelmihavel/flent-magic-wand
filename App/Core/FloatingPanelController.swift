import AppKit
import SwiftUI
import QuartzCore

/// Controls the floating panel window that expands from a pill shape near the notch,
/// mimicking Apple's Dynamic Island expansion/collapse behavior.
final class FloatingPanelController {
    private var panel: NSPanel!
    private let appState: AppState
    private var isAnimating = false

    // Geometry
    private let pillWidth: CGFloat = 180
    private let pillHeight: CGFloat = 36
    private let expandedWidth: CGFloat = 380
    private let expandedHeight: CGFloat = 380
    private let cornerRadius: CGFloat = 20

    init(appState: AppState) {
        self.appState = appState
    }

    func prewarm() {
        createPanel()
        panel.layoutIfNeeded()
    }

    // MARK: - Show (Pill → Panel)

    func showPanel(relativeTo statusItem: NSStatusItem) {
        guard !isAnimating else { return }
        guard let screen = NSScreen.main else { return }
        isAnimating = true

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarBottom = visibleFrame.maxY

        // Pill: flush against menu bar, centered at notch
        let pillX = screenFrame.midX - pillWidth / 2
        let pillY = menuBarBottom - pillHeight
        let pillFrame = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        // Expanded: top edge flush with menu bar
        let expandedX = screenFrame.midX - expandedWidth / 2
        let expandedY = menuBarBottom - expandedHeight
        let expandedFrame = NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)

        // Start as pill
        panel.setFrame(pillFrame, display: false)
        panel.alphaValue = 0
        setCornerRadius(pillHeight / 2)
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [self] in
            // Fade in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }

            // Expand
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                ctx.allowsImplicitAnimation = true
                self.panel.animator().setFrame(expandedFrame, display: true)
            }, completionHandler: { [weak self] in
                self?.isAnimating = false
            })

            animateCornerRadius(from: pillHeight / 2, to: cornerRadius, duration: 0.45)

            Task { @MainActor in
                self.appState.isPanelVisible = true
            }
        }
    }

    // MARK: - Hide (Panel → Pill → gone)

    func hidePanel() {
        guard !isAnimating else { return }
        guard let screen = NSScreen.main else { return }
        isAnimating = true

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarBottom = visibleFrame.maxY

        let pillX = screenFrame.midX - pillWidth / 2
        let pillY = menuBarBottom - pillHeight
        let pillFrame = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        // Shrink + fade simultaneously
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.7, 0.2)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(pillFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.isAnimating = false
            Task { @MainActor in
                self.appState.isPanelVisible = false
            }
        })

        animateCornerRadius(from: cornerRadius, to: pillHeight / 2, duration: 0.28)
    }

    // MARK: - Corner Radius Animation

    private func setCornerRadius(_ radius: CGFloat) {
        panel.contentView?.superview?.layer?.cornerRadius = radius
        panel.contentView?.layer?.cornerRadius = radius
    }

    private func animateCornerRadius(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        let layers = [panel.contentView?.superview?.layer, panel.contentView?.layer].compactMap { $0 }
        for layer in layers {
            let anim = CABasicAnimation(keyPath: "cornerRadius")
            anim.fromValue = from
            anim.toValue = to
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "cornerRadius")
            layer.cornerRadius = to
        }
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let contentView = MainContentView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true

        // Borderless panel — no titlebar, so all 4 corners are truly equal
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: expandedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Apply corner radius to the window's root layer — all 4 corners equal
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = cornerRadius
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.cornerCurve = .continuous

        // Also round the window frame view (superview of contentView)
        if let frameView = panel.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = cornerRadius
            frameView.layer?.masksToBounds = true
            frameView.layer?.cornerCurve = .continuous
        }

        // Disable implicit layer animations
        panel.contentView?.layer?.actions = ["position": NSNull(), "bounds": NSNull()]

        self.panel = panel
    }
}
