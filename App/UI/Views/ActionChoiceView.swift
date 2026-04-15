import SwiftUI

/// Post-upload state: shows the chosen image(s) and lets the user pick what to do.
struct ActionChoiceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            InputPreview()
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(ProcessingAction.allCases) { action in
                    ActionCard(action: action) {
                        withAnimation(.smooth(duration: 0.35)) {
                            appState.startAction(action)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct InputPreview: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                ThumbnailStack(items: appState.inputs)

                if appState.inputs.count > 1 {
                    Text("\(appState.inputs.count) images")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(.black.opacity(0.55))
                        )
                        .padding(10)
                }
            }

            DismissImageButton {
                withAnimation(.smooth(duration: 0.3)) {
                    appState.reset()
                }
            }
            .padding(8)
        }
    }
}

private struct ThumbnailStack: View {
    let items: [InputItem]

    var body: some View {
        if let first = items.first, items.count == 1 {
            Image(nsImage: first.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            // Fanned stack of up to 3 thumbnails
            ZStack {
                ForEach(Array(items.prefix(3).enumerated()).reversed(), id: \.element.id) { idx, item in
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                        .rotationEffect(.degrees(Double(idx - 1) * 3.5))
                        .offset(x: CGFloat(idx - 1) * 10, y: CGFloat(idx) * 4)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ActionCard: View {
    let action: ProcessingAction
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(action.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
