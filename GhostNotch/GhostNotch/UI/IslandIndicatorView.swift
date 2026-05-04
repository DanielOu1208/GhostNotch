import SwiftUI

struct IslandIndicatorView: View {
    let isHovering: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.55), radius: 5)

            Text(">_")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))

            if isHovering {
                Text("ready")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, isHovering ? 14 : 12)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
