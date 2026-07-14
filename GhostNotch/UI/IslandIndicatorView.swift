import AppKit
import SwiftUI

struct IslandIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var sessionState: TerminalSessionState
    @ObservedObject var presetStore: AgentPresetStore
    @Namespace private var directorySelectionNamespace

    let isHovering: Bool
    let selectedDirectoryPresetID: AgentLaunchDirectoryPreset.ID?
    let onSelectDirectory: (AgentLaunchDirectoryPreset) -> Void
    let onLaunchAgent: (AgentLauncher) -> Void

    var body: some View {
        ZStack {
            if isHovering {
                hoverIndicator
                    .transition(hoverTransition)
            } else {
                collapsedIndicator
                    .transition(collapsedTransition)
            }
        }
    }

    private var hoverEntryAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: IslandTransitionPlan.reduceMotionDuration)
        }

        let delay = IslandTransitionPlan.hoverOpenDuration
            * IslandTransitionPlan.primaryContentEntryDelayFraction
        return .easeOut(duration: IslandTransitionPlan.hoverOpenDuration - delay)
            .delay(delay)
    }

    private var collapsedExitAnimation: Animation {
        let duration = reduceMotion
            ? IslandTransitionPlan.reduceMotionDuration
            : IslandTransitionPlan.hoverOpenDuration
                * IslandTransitionPlan.outgoingContentDurationFraction
        return .easeOut(duration: duration)
    }

    private var compactCloseAnimation: Animation {
        .easeOut(
            duration: reduceMotion
                ? IslandTransitionPlan.reduceMotionDuration
                : IslandTransitionPlan.hoverCloseDuration
        )
    }

    private var hoverTransition: AnyTransition {
        return .asymmetric(
            insertion: .opacity.animation(hoverEntryAnimation),
            removal: .opacity.animation(compactCloseAnimation)
        )
    }

    private var collapsedTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(compactCloseAnimation),
            removal: .opacity.animation(collapsedExitAnimation)
        )
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
        let directoryPresets = visibleDirectoryPresets
        let enabledLaunchers = presetStore.enabledLaunchers

        return HStack(alignment: .bottom, spacing: 0) {
            hoverStatus
                .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(alignment: .bottom, spacing: 12) {
                if !directoryPresets.isEmpty {
                    VStack(spacing: IslandMetrics.hoverControlLabelSpacing) {
                        Text("Folders")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(height: IslandMetrics.hoverControlLabelHeight)

                        directoryPresetControls(directoryPresets)
                    }
                }

                if !enabledLaunchers.isEmpty {
                    VStack(spacing: IslandMetrics.hoverControlLabelSpacing) {
                        Text("Agents")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(height: IslandMetrics.hoverControlLabelHeight)

                        HStack(alignment: .center, spacing: 0) {
                            ForEach(enabledLaunchers) { launcher in
                                AgentLauncherButton(launcher: launcher) {
                                    onLaunchAgent(launcher)
                                }
                            }
                        }
                        .notchCapsuleGroupStyle()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 24)
        .padding(.bottom, IslandMetrics.hoverControlBottomPadding)
    }

    private var visibleDirectoryPresets: [AgentLaunchDirectoryPreset] {
        Array(
            presetStore.directoryPresets
                .filter { $0.directoryExists() }
                .prefix(AgentPresetStore.maximumDirectoryPresets)
        )
    }

    private func directoryPresetControls(
        _ directoryPresets: [AgentLaunchDirectoryPreset]
    ) -> some View {
        ZStack {
            if !reduceTransparency {
                directorySelectionLayer(directoryPresets, usesOpaqueGlass: false)
                    .padding(IslandMetrics.notchCapsuleGroupInset)
            }

            HStack(alignment: .center, spacing: 0) {
                ForEach(directoryPresets) { preset in
                    DirectoryPresetButton(
                        preset: preset,
                        isSelected: preset.id == selectedDirectoryPresetID,
                        selectionColor: directorySelectionColor,
                        selectionNamespace: directorySelectionNamespace,
                        selectionTransition: directorySelectionTransition
                    ) {
                        onSelectDirectory(preset)
                    }
                }
            }
            .background {
                if reduceTransparency {
                    directorySelectionLayer(directoryPresets, usesOpaqueGlass: true)
                }
            }
            .notchCapsuleGroupStyle()
        }
        .animation(directorySelectionAnimation, value: selectedDirectoryPresetID)
    }

    private func directorySelectionLayer(
        _ directoryPresets: [AgentLaunchDirectoryPreset],
        usesOpaqueGlass: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(directoryPresets) { preset in
                ZStack {
                    if preset.id == selectedDirectoryPresetID {
                        directorySelectionCapsule(usesOpaqueGlass: usesOpaqueGlass)
                            .matchedGeometryEffect(
                                id: usesOpaqueGlass ? "opaque-directory-selection" : "directory-selection",
                                in: directorySelectionNamespace
                            )
                            .transition(directorySelectionTransition)
                    }
                }
                .frame(
                    width: IslandMetrics.notchControlWidth,
                    height: IslandMetrics.notchControlHeight
                )
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func directorySelectionCapsule(usesOpaqueGlass: Bool) -> some View {
        Group {
            if usesOpaqueGlass {
                Color.clear
                    .glassEffect(
                        .regular.tint(directorySelectionColor),
                        in: Capsule()
                    )
                    .clipShape(Capsule())
            } else {
                Capsule()
                    .fill(directorySelectionColor)
            }
        }
        .frame(
            width: IslandMetrics.notchControlWidth + IslandMetrics.notchCapsuleGroupInset + 1,
            height: IslandMetrics.notchControlHeight + IslandMetrics.notchCapsuleGroupInset + 1
        )
    }

    private var directorySelectionColor: Color {
        Color(nsColor: .systemBlue).mix(with: .white, by: 0.18)
    }

    private var directorySelectionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18, extraBounce: 0.02)
    }

    private var directorySelectionTransition: AnyTransition {
        .opacity.animation(.easeOut(duration: reduceMotion ? 0.08 : 0.12))
    }

    private var hoverStatus: some View {
        HStack(alignment: .center, spacing: 4) {
            hoverStatusDot

            HoverStatusText(state: renderedAgentActivityState)
                .lineLimit(1)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(height: IslandMetrics.notchControlHeight, alignment: .center)
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

private struct DirectoryPresetButton: View {
    let preset: AgentLaunchDirectoryPreset
    let isSelected: Bool
    let selectionColor: Color
    let selectionNamespace: Namespace.ID
    let selectionTransition: AnyTransition
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(selectionColor)
                        .frame(
                            width: IslandMetrics.notchControlWidth
                                - IslandMetrics.notchCapsuleGroupInset * 2,
                            height: IslandMetrics.notchControlHeight
                                - IslandMetrics.notchCapsuleGroupInset * 2
                        )
                        .matchedGeometryEffect(
                            id: "foreground-directory-selection",
                            in: selectionNamespace
                        )
                        .transition(selectionTransition)
                }

                Text(displayIcon)
                    .font(iconFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.primary)
            }
            .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
            .contentShape(Capsule())
        }
        .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
        .notchControlStyle()
        .accessibilityLabel("Use \(preset.displayLabel) folder")
        .help("\(preset.displayLabel) - \(preset.path)")
    }

    private var iconFont: Font {
        .system(size: displayIcon.count == 1 ? 15 : 11, weight: .semibold)
    }

    private var displayIcon: String {
        DirectoryPresetIcon.displayValue(icon: preset.icon, fallbackSource: preset.displayLabel)
    }
}

private struct AgentLauncherButton: View {
    let launcher: AgentLauncher
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(launcher.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 17, height: 17)
                .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
                .contentShape(Capsule())
        }
        .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
        .notchControlStyle()
        .accessibilityLabel(launcher.accessibilityLabel)
        .help(launcher.helpText)
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
            .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
        }
    }

    private func dotCount(at date: Date) -> Int {
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed / Self.dotStepDuration) % 4
    }

    private static let font = Font.caption.weight(.medium)
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
