import SwiftUI

/// Root view that switches between states with animated transitions.
struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var contentReady = false

    var body: some View {
        ZStack {
            // Solid dark base to prevent see-through, then vibrancy on top
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)

            if contentReady {
                VStack(spacing: 0) {
                    HeaderBar()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Spacer(minLength: 0)

                    Group {
                        switch appState.phase {
                        case .idle:
                            IdleView()
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))

                        case .awaitingAction:
                            ActionChoiceView()
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))

                        case .uploading, .processing:
                            ProcessingView()
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))

                        case .complete:
                            ResultView()
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                ))

                        case .failed:
                            ErrorView()
                                .transition(.opacity)
                        }
                    }
                    .animation(.smooth(duration: 0.4), value: appState.phase)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 120, maxWidth: .infinity, minHeight: 36, maxHeight: .infinity)
        // Freeze content during close — never tear down while panel is collapsing.
        // Reset only happens via isPanelVisible going true (next open).
        .onChange(of: appState.isPanelVisible) { _, visible in
            if visible {
                // Panel is opening — brief delay then show content
                contentReady = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        contentReady = true
                    }
                }
            }
            // On close: do nothing — let the panel animate away with frozen content
        }
        .onAppear {
            // First launch
            if !contentReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        contentReady = true
                    }
                }
            }
        }
    }
}

// MARK: - Header Bar

struct HeaderBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Magic Wand")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(height: 28)
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
