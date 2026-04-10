import SwiftUI

/// Freeform lasso drawing overlay — captures a closed polygon of normalized [0,1] points.
/// Renders a smooth glowing stroke while drawing and pulses on completion.
struct LassoOverlay: View {
    @Binding var isActive: Bool
    let onComplete: ([[Double]]) -> Void

    @State private var points: [CGPoint] = []
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Semi-transparent scrim while lasso is active
                Color.black.opacity(0.15)

                // Lasso path
                if points.count >= 2 {
                    LassoPath(points: points, closed: !isDragging)
                        .stroke(
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.6), radius: 4)
                        .shadow(color: .blue.opacity(0.3), radius: 8)
                }

                // Invisible drag surface
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    points = []
                                }
                                let pt = value.location
                                // Clamp to bounds
                                let clamped = CGPoint(
                                    x: min(max(pt.x, 0), geo.size.width),
                                    y: min(max(pt.y, 0), geo.size.height)
                                )
                                points.append(clamped)
                            }
                            .onEnded { _ in
                                isDragging = false
                                guard points.count >= 10 else {
                                    points = []
                                    return
                                }
                                // Normalize to [0, 1]
                                let normalized = points.map { pt in
                                    [
                                        Double(pt.x / geo.size.width),
                                        Double(pt.y / geo.size.height),
                                    ]
                                }
                                // Simplify to reduce point count
                                let simplified = simplifyPolygon(normalized, tolerance: 0.005)
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isActive = false
                                }
                                onComplete(simplified)
                                points = []
                            }
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Douglas-Peucker polygon simplification.
    private func simplifyPolygon(_ pts: [[Double]], tolerance: Double) -> [[Double]] {
        guard pts.count > 20 else { return pts }

        func perpDist(_ p: [Double], _ a: [Double], _ b: [Double]) -> Double {
            let dx = b[0] - a[0], dy = b[1] - a[1]
            let len2 = dx * dx + dy * dy
            guard len2 > 0 else { return hypot(p[0] - a[0], p[1] - a[1]) }
            let t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2))
            return hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))
        }

        func simplify(_ pts: [[Double]], _ eps: Double) -> [[Double]] {
            guard pts.count > 2 else { return pts }
            var maxDist = 0.0, maxIdx = 0
            for i in 1..<pts.count - 1 {
                let d = perpDist(pts[i], pts[0], pts[pts.count - 1])
                if d > maxDist { maxDist = d; maxIdx = i }
            }
            if maxDist > eps {
                let left = simplify(Array(pts[...maxIdx]), eps)
                let right = simplify(Array(pts[maxIdx...]), eps)
                return left.dropLast() + right
            }
            return [pts[0], pts[pts.count - 1]]
        }

        return simplify(pts, tolerance)
    }
}

/// Shape that draws the lasso path.
private struct LassoPath: Shape {
    let points: [CGPoint]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }
}
