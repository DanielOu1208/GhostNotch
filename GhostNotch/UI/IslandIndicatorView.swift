import SwiftUI

struct IslandIndicatorView: View {
    @ObservedObject var sessionState: TerminalSessionState

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
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }

    @ViewBuilder
    private var collapsedStatusDot: some View {
        switch renderedAgentActivityState {
        case .idle:
            StaticAgentStatusDot(
                color: AgentStatusDotStyle.idleGreen,
                opacity: 1,
                shadowColor: AgentStatusDotStyle.idleGreen.opacity(0.84),
                shadowRadius: 6
            )
        case .working:
            BreathingAgentStatusDot(
                color: .white,
                brightShadowRadius: 10
            )
        case .attention:
            BreathingAgentStatusDot(
                color: AgentStatusDotStyle.attentionBlue,
                brightShadowRadius: 11
            )
        }
    }

    private var renderedAgentActivityState: TerminalAgentActivityState {
        sessionState.isRunning ? sessionState.agentActivityState : .idle
    }

    private var collapsedGhosttyLogo: some View {
        ZStack(alignment: .bottom) {
            GhosttyMarkShape()
                .fill(.white)
                .overlay {
                    GhosttyMarkShape()
                        .stroke(.white.opacity(0.72), lineWidth: 0.7)
                }
                .shadow(color: .white.opacity(0.28), radius: 4)

            HStack(spacing: 3) {
                Circle()
                    .fill(.black.opacity(0.82))
                    .frame(width: 2.4, height: 2.4)

                Circle()
                    .fill(.black.opacity(0.82))
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
        min(IslandMetrics.currentNotchReferenceWidth, IslandMetrics.collapsedSize.width)
    }

    private var hoverIndicator: some View {
        VStack(spacing: 6) {
            Text("default shell ready")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .transition(.opacity.combined(with: .move(edge: .top)))

            HStack(alignment: .center, spacing: 9) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: .white.opacity(0.58), radius: 5)

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
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
}

private struct StaticAgentStatusDot: View {
    let color: Color
    let opacity: Double
    let shadowColor: Color
    let shadowRadius: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .shadow(color: shadowColor, radius: shadowRadius)
    }
}

private struct BreathingAgentStatusDot: View {
    let color: Color
    let brightShadowRadius: CGFloat

    @State private var isBright = false

    var body: some View {
        Circle()
            .fill(isBright ? color : .black)
            .frame(width: 6, height: 6)
            .shadow(
                color: color.opacity(isBright ? 0.92 : 0),
                radius: isBright ? brightShadowRadius : 0
            )
            .animation(.easeInOut(duration: 1.28).repeatForever(autoreverses: true), value: isBright)
            .onAppear {
                isBright = true
            }
    }
}

private enum AgentStatusDotStyle {
    static let idleGreen = Color(red: 0.12, green: 1, blue: 0.34)
    static let attentionBlue = Color(red: 0.18, green: 0.58, blue: 1)
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
