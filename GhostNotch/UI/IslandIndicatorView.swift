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
            collapsedGhosttyLogo
                .frame(width: collapsedSideExtensionWidth, height: collapsedIndicatorHeight)

            Color.clear
                .frame(width: collapsedCenterGapWidth, height: collapsedIndicatorHeight)

            collapsedStatusDot
                .frame(width: collapsedSideExtensionWidth, height: collapsedIndicatorHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var collapsedStatusDot: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .shadow(color: .green.opacity(0.62), radius: 5)
    }

    private var collapsedGhosttyLogo: some View {
        ZStack(alignment: .bottom) {
            GhosttyMarkShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.84, blue: 1.0),
                            Color(red: 0.44, green: 0.55, blue: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    GhosttyMarkShape()
                        .stroke(.white.opacity(0.72), lineWidth: 0.7)
                }
                .shadow(color: Color(red: 0.44, green: 0.55, blue: 0.96).opacity(0.45), radius: 4)

            HStack(spacing: 3) {
                Circle()
                    .fill(.black.opacity(0.74))
                    .frame(width: 2.4, height: 2.4)

                Circle()
                    .fill(.black.opacity(0.74))
                    .frame(width: 2.4, height: 2.4)
            }
            .padding(.bottom, 6.2)
        }
        .frame(width: 16, height: 17)
    }

    private var collapsedIndicatorHeight: CGFloat {
        IslandMetrics.collapsedSize.height
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

            HStack(alignment: .center, spacing: 9) {
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

private struct GhosttyMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let bottom = rect.maxY
        let top = rect.minY + height * 0.08
        let left = rect.minX + width * 0.16
        let right = rect.maxX - width * 0.16

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: top))
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.minY + height * 0.4),
            control: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: bottom - height * 0.24))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - width * 0.32, y: bottom - height * 0.12),
            control: CGPoint(x: rect.maxX - width * 0.1, y: bottom - height * 0.12)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: bottom - height * 0.11),
            control: CGPoint(x: rect.maxX - width * 0.42, y: bottom - height * 0.28)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.32, y: bottom - height * 0.12),
            control: CGPoint(x: rect.minX + width * 0.42, y: bottom - height * 0.28)
        )
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - height * 0.24),
            control: CGPoint(x: rect.minX + width * 0.1, y: bottom - height * 0.12)
        )
        path.addLine(to: CGPoint(x: left, y: rect.minY + height * 0.4))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: top),
            control: CGPoint(x: left, y: top)
        )
        path.closeSubpath()

        return path
    }
}
