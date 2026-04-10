import SwiftUI

/// Shown when processing fails.
struct ErrorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.red.opacity(0.8))

            if case .failed(let message) = appState.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button("Try Again") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    appState.reset()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 20)
    }
}
