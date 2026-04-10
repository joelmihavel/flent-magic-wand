import SwiftUI

/// Stylized drop zone with animated border and icon.
struct DropZoneView: View {
    @Binding var isDragHovering: Bool
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(isDragHovering ? Color.accentColor : Color.secondary)
                .scaleEffect(isDragHovering ? 1.1 : 1.0)

            VStack(spacing: 4) {
                Text("Drop image here")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDragHovering ? .primary : .secondary)

                Text("or click below to upload")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDragHovering ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: isDragHovering ? 2 : 1.5,
                        dash: [8, 6],
                        dashPhase: dashPhase
                    )
                )
                .foregroundStyle(isDragHovering ? Color.accentColor : Color.gray.opacity(0.3))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragHovering)
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                dashPhase = 28
            }
        }
    }
}
