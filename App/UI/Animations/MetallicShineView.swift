import SwiftUI

/// A metallic surface with a sweeping light reflection — like light glinting off polished metal.
/// Fully opaque, visible on any background. Rendered at 60fps via Canvas + TimelineView.
struct MetallicShineView: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height

                // Solid opaque base — dark gunmetal chrome
                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .color(Color(red: 0.10, green: 0.10, blue: 0.12))
                )

                // Metallic gradient overlay — gives depth
                let baseGradient = Gradient(colors: [
                    Color(white: 0.22),
                    Color(white: 0.16),
                    Color(white: 0.24),
                    Color(white: 0.14),
                    Color(white: 0.20),
                ])
                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .linearGradient(
                        baseGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: h)
                    )
                )

                // Brushed metal texture lines
                for i in stride(from: 0.0, to: Double(h), by: 1.5) {
                    let brightness = 0.22 + 0.06 * sin(i * 0.9 + t * 0.3)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: i))
                    path.addLine(to: CGPoint(x: w, y: i))
                    context.stroke(
                        path,
                        with: .color(Color(white: brightness).opacity(0.4)),
                        lineWidth: 0.5
                    )
                }

                // Primary light sweep — bright beam
                let sweepPeriod = 2.5
                let sweepPhase = fmod(t, sweepPeriod) / sweepPeriod
                let sweepX = -w * 0.4 + (w * 1.8) * sweepPhase

                let beamWidth: CGFloat = w * 0.4
                let beamGradient = Gradient(colors: [
                    .white.opacity(0),
                    .white.opacity(0.1),
                    .white.opacity(0.4),
                    .white.opacity(0.7),
                    .white.opacity(0.4),
                    .white.opacity(0.1),
                    .white.opacity(0),
                ])

                context.drawLayer { ctx in
                    let beamRect = CGRect(
                        x: sweepX - beamWidth / 2,
                        y: -h * 0.2,
                        width: beamWidth,
                        height: h * 1.4
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

                // Secondary glint — narrower, offset
                let glintPhase = fmod(t + 1.3, sweepPeriod) / sweepPeriod
                let glintX = -w * 0.3 + (w * 1.6) * glintPhase
                let glintWidth: CGFloat = w * 0.15

                let glintGradient = Gradient(colors: [
                    .white.opacity(0),
                    .white.opacity(0.25),
                    .white.opacity(0.55),
                    .white.opacity(0.25),
                    .white.opacity(0),
                ])

                context.drawLayer { ctx in
                    let glintRect = CGRect(
                        x: glintX - glintWidth / 2,
                        y: -h * 0.1,
                        width: glintWidth,
                        height: h * 1.2
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

                // Top edge highlight — polished rim
                let rimStrength = 0.15 + 0.05 * sin(t * 1.5)
                let edgeGrad = Gradient(colors: [
                    .white.opacity(rimStrength),
                    .white.opacity(rimStrength * 0.3),
                    .clear,
                ])
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: w, height: h * 0.2)),
                    with: .linearGradient(
                        edgeGrad,
                        startPoint: CGPoint(x: w / 2, y: 0),
                        endPoint: CGPoint(x: w / 2, y: h * 0.2)
                    )
                )

                // Bottom edge — subtle reflection
                let bottomGrad = Gradient(colors: [
                    .clear,
                    .white.opacity(0.06),
                ])
                context.fill(
                    Path(CGRect(x: 0, y: h * 0.85, width: w, height: h * 0.15)),
                    with: .linearGradient(
                        bottomGrad,
                        startPoint: CGPoint(x: w / 2, y: h * 0.85),
                        endPoint: CGPoint(x: w / 2, y: h)
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
