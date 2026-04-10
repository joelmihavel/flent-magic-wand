import SwiftUI

// MARK: - Spring Presets

/// Curated spring configurations matching Apple's motion language.
enum SpringPreset {
    /// Quick, snappy interaction feedback (buttons, toggles).
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.75)

    /// Default panel/modal presentation.
    static let panel = Animation.spring(response: 0.45, dampingFraction: 0.82)

    /// Smooth, gentle expansion (result view).
    static let expand = Animation.spring(response: 0.55, dampingFraction: 0.78)

    /// Bouncy entry for emphasis.
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.65)
}

// MARK: - Notch Origin Modifier

/// Applies a scale + opacity transition originating from the top-center (notch).
struct NotchOriginModifier: ViewModifier {
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPresented ? 1.0 : 0.92, anchor: .top)
            .opacity(isPresented ? 1.0 : 0.0)
            .offset(y: isPresented ? 0 : -8)
            .animation(SpringPreset.panel, value: isPresented)
    }
}

extension View {
    func notchTransition(isPresented: Bool) -> some View {
        modifier(NotchOriginModifier(isPresented: isPresented))
    }
}

// MARK: - Phase Transition Modifier

/// Animated transition between processing phases with scale + opacity.
struct PhaseTransitionModifier: ViewModifier {
    let phase: ProcessingPhase

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1.0 : 0.95)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(SpringPreset.panel) {
                    appeared = true
                }
            }
            .onChange(of: phase) { _, _ in
                appeared = false
                withAnimation(SpringPreset.panel) {
                    appeared = true
                }
            }
    }
}

extension View {
    func phaseTransition(for phase: ProcessingPhase) -> some View {
        modifier(PhaseTransitionModifier(phase: phase))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.1),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .onAppear {
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        phase = 400
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
