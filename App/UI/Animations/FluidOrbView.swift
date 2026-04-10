import SwiftUI

/// An organic, fluid animated orb mimicking Apple's Dynamic Island activity indicators.
/// Uses Canvas + TimelineView for smooth 60fps animation without Metal shaders.
struct FluidOrbView: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) / 2

                // Draw 3 overlapping soft blobs that orbit and pulse
                let blobs: [(Color, Double, Double, Double)] = [
                    (.purple, 0.4, 1.0, 0.0),
                    (.blue, 0.35, 1.3, 2.1),
                    (.cyan, 0.3, 0.7, 4.2),
                ]

                for (color, orbitRadius, speed, phase) in blobs {
                    let angle = t * speed + phase
                    let blobCenter = CGPoint(
                        x: center.x + cos(angle) * radius * orbitRadius,
                        y: center.y + sin(angle * 0.7 + phase) * radius * orbitRadius
                    )

                    let pulse = 0.7 + 0.3 * sin(t * 2.0 + phase)
                    let blobSize = radius * 0.8 * pulse

                    let gradient = Gradient(colors: [
                        color.opacity(0.8),
                        color.opacity(0.4),
                        color.opacity(0.0),
                    ])

                    let rect = CGRect(
                        x: blobCenter.x - blobSize,
                        y: blobCenter.y - blobSize,
                        width: blobSize * 2,
                        height: blobSize * 2
                    )

                    context.fill(
                        Circle().path(in: rect),
                        with: .radialGradient(
                            gradient,
                            center: blobCenter,
                            startRadius: 0,
                            endRadius: blobSize
                        )
                    )
                }

                // Global pulse overlay
                let globalPulse = 0.85 + 0.15 * sin(t * 2.5)
                context.opacity = globalPulse
            }
            .compositingGroup()
            .blur(radius: size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
    }
}
