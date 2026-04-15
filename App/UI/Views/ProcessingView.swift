import SwiftUI

/// Shows the input image as a desaturated skeleton with a full-surface metallic shimmer sweep.
struct ProcessingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Skeleton image with shimmer overlay
            if let inputImage = appState.primaryInput?.image {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        // Desaturated + dimmed input image as skeleton
                        Image(nsImage: inputImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .saturation(0)
                            .brightness(-0.15)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Full-surface shimmer overlay
                        ShimmerOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .allowsHitTesting(false)
                    }

                    // X button to cancel
                    DismissImageButton {
                        withAnimation(.smooth(duration: 0.35)) {
                            appState.reset()
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 240)
                .padding(.horizontal, 20)
            }

            // Status text
            VStack(spacing: 6) {
                Text(appState.phase.statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text("Processing on-device...")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            // Back button — abort processing and return to action selection
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    appState.backToActionChoice()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(.quaternary.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 0)
    }
}

// MARK: - Full-surface shimmer overlay

/// A metallic light sweep that covers the entire surface — like light glinting across brushed metal.
/// Uses Canvas + TimelineView at a reduced update rate to avoid GPU contention during processing.
struct ShimmerOverlay: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let w = size.width
                let h = size.height

                // Semi-transparent dark overlay to dim the skeleton
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color.black.opacity(0.25))
                )

                // Primary sweep beam — wide enough to cover the full surface
                let period = 2.0
                let phase = fmod(t, period) / period
                let sweepX = -w * 0.8 + (w * 2.6) * phase
                let beamWidth = w * 0.8

                let beamGradient = Gradient(colors: [
                    .white.opacity(0),
                    .white.opacity(0.04),
                    .white.opacity(0.12),
                    .white.opacity(0.22),
                    .white.opacity(0.12),
                    .white.opacity(0.04),
                    .white.opacity(0),
                ])

                // Diagonal beam
                context.drawLayer { ctx in
                    ctx.rotate(by: .degrees(-20))
                    let beamRect = CGRect(
                        x: sweepX - beamWidth / 2,
                        y: -h * 0.8,
                        width: beamWidth,
                        height: h * 2.6
                    )
                    ctx.fill(
                        Path(beamRect),
                        with: .linearGradient(
                            beamGradient,
                            startPoint: CGPoint(x: beamRect.minX, y: h / 2),
                            endPoint: CGPoint(x: beamRect.maxX, y: h / 2)
                        )
                    )
                }

                // Secondary narrower glint — offset timing
                let glintPhase = fmod(t + 0.8, period) / period
                let glintX = -w * 0.6 + (w * 2.2) * glintPhase
                let glintWidth = w * 0.3

                let glintGradient = Gradient(colors: [
                    .white.opacity(0),
                    .white.opacity(0.08),
                    .white.opacity(0.18),
                    .white.opacity(0.08),
                    .white.opacity(0),
                ])

                context.drawLayer { ctx in
                    ctx.rotate(by: .degrees(-20))
                    let glintRect = CGRect(
                        x: glintX - glintWidth / 2,
                        y: -h * 0.6,
                        width: glintWidth,
                        height: h * 2.2
                    )
                    ctx.fill(
                        Path(glintRect),
                        with: .linearGradient(
                            glintGradient,
                            startPoint: CGPoint(x: glintRect.minX, y: h / 2),
                            endPoint: CGPoint(x: glintRect.maxX, y: h / 2)
                        )
                    )
                }
            }
        }
    }
}
