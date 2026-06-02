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
        let style = AgentStatusDotStyle.style(for: renderedAgentActivityState)

        switch style.animation {
        case .static:
            StaticAgentStatusDot(
                color: style.color,
                opacity: style.opacity,
                shadowColor: style.shadowColor,
                shadowRadius: style.shadowRadius
            )
        case .breathing:
            BreathingAgentStatusDot(
                color: style.color,
                brightShadowRadius: style.shadowRadius
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
                hoverStatusDot

                HoverStatusText(state: renderedAgentActivityState)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 15)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }

    @ViewBuilder
    private var hoverStatusDot: some View {
        let style = AgentStatusDotStyle.style(for: renderedAgentActivityState)

        switch style.animation {
        case .static:
            StaticAgentStatusDot(
                color: style.color,
                opacity: style.opacity,
                shadowColor: style.shadowColor,
                shadowRadius: style.shadowRadius,
                diameter: 7
            )
        case .breathing:
            BreathingAgentStatusDot(
                color: style.color,
                brightShadowRadius: style.shadowRadius,
                diameter: 7
            )
        }
    }
}

private struct StaticAgentStatusDot: View {
    let color: Color
    let opacity: Double
    let shadowColor: Color
    let shadowRadius: CGFloat
    let diameter: CGFloat

    init(
        color: Color,
        opacity: Double,
        shadowColor: Color,
        shadowRadius: CGFloat,
        diameter: CGFloat = 6
    ) {
        self.color = color
        self.opacity = opacity
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.diameter = diameter
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .opacity(opacity)
            .shadow(color: shadowColor, radius: shadowRadius)
    }
}

private struct BreathingAgentStatusDot: View {
    let color: Color
    let brightShadowRadius: CGFloat
    let diameter: CGFloat

    init(color: Color, brightShadowRadius: CGFloat, diameter: CGFloat = 6) {
        self.color = color
        self.brightShadowRadius = brightShadowRadius
        self.diameter = diameter
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let intensity = breathingIntensity(at: timeline.date)

            Circle()
                .fill(.black)
                .overlay {
                    Circle()
                        .fill(color.opacity(intensity))
                }
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: color.opacity(0.92 * intensity),
                    radius: brightShadowRadius * intensity
                )
        }
    }

    private func breathingIntensity(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let cycleProgress = elapsed.truncatingRemainder(dividingBy: Self.fullCycleDuration) / Self.fullCycleDuration
        let triangularProgress = cycleProgress < 0.5 ? cycleProgress * 2 : (1 - cycleProgress) * 2

        return pow(triangularProgress, Self.blackEndpointCompression)
    }

    private static let halfCycleDuration: TimeInterval = 1.024
    private static let fullCycleDuration = halfCycleDuration * 2
    private static let blackEndpointCompression = 0.7
}

private struct HoverStatusText: View {
    let state: TerminalAgentActivityState

    var body: some View {
        switch state {
        case .idle:
            statusText("Ready")
        case .working:
            animatedStatusText("Working")
        case .attention:
            animatedStatusText("Waiting")
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(Self.font)
            .foregroundStyle(.white.opacity(0.68))
    }

    private func animatedStatusText(_ text: String) -> some View {
        TimelineView(.animation) { timeline in
            let dots = String(repeating: ".", count: dotCount(at: timeline.date))

            HStack(spacing: 0) {
                Text(text)

                Text(dots)
                    .frame(width: 18, alignment: .leading)
            }
            .font(Self.font)
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    private func dotCount(at date: Date) -> Int {
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed / Self.dotStepDuration) % 4
    }

    private static let font = Font.system(size: 12, weight: .semibold, design: .rounded)
    private static let dotStepDuration: TimeInterval = 0.42
}

private struct AgentStatusDotStyle {
    enum Animation {
        case `static`
        case breathing
    }

    let animation: Animation
    let color: Color
    let opacity: Double
    let shadowColor: Color
    let shadowRadius: CGFloat

    static func style(for state: TerminalAgentActivityState) -> AgentStatusDotStyle {
        switch state {
        case .idle:
            return AgentStatusDotStyle(
                animation: .static,
                color: idleGreen,
                opacity: 1,
                shadowColor: idleGreen.opacity(0.84),
                shadowRadius: 6
            )
        case .working:
            return AgentStatusDotStyle(
                animation: .breathing,
                color: .white,
                opacity: 1,
                shadowColor: .white,
                shadowRadius: 10
            )
        case .attention:
            return AgentStatusDotStyle(
                animation: .breathing,
                color: attentionBlue,
                opacity: 1,
                shadowColor: attentionBlue,
                shadowRadius: 10
            )
        }
    }

    private static let idleGreen = Color(red: 0.12, green: 1, blue: 0.34)
    private static let attentionBlue = Color(red: 0.18, green: 0.58, blue: 1)
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
