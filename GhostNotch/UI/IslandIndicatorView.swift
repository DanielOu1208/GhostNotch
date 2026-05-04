import SwiftUI

struct IslandIndicatorView: View {
    let isHovering: Bool

    var body: some View {
        if isHovering {
            hoverIndicator
        } else {
            collapsedIndicator
        }
    }

    private var collapsedIndicator: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.62), radius: 5)
                .frame(width: collapsedSideExtensionWidth)

            Color.clear
                .frame(width: collapsedCenterGapWidth)

            Text(">_")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: collapsedSideExtensionWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 11)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var collapsedSideExtensionWidth: CGFloat {
        max((IslandMetrics.collapsedSize.width - collapsedCenterGapWidth) / 2, 0)
    }

    private var collapsedCenterGapWidth: CGFloat {
        min(IslandMetrics.physicalNotchReferenceWidth, IslandMetrics.collapsedSize.width)
    }

    private var hoverIndicator: some View {
        VStack(spacing: 6) {
            Text("default shell ready")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .transition(.opacity.combined(with: .move(edge: .top)))

            HStack(spacing: 9) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: .green.opacity(0.58), radius: 5)

                Text(">_")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))

                Text("ready")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 15)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
