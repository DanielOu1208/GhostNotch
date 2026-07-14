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

            if !isHovering {
                collapsedAgentLogoLayer
                    .transition(collapsedAgentTransition)
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

    private var collapsedAgentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(compactCloseAnimation),
            removal: .identity
        )
    }

    private var collapsedIndicator: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: collapsedSideExtensionWidth, height: collapsedIndicatorHeight)

            Color.clear
                .frame(width: collapsedCenterGapWidth, height: collapsedIndicatorHeight)

            RoseThreeStatusIndicator(
                state: renderedAgentActivityState,
                reducesMotion: reduceMotion
            )
                .padding(.bottom, collapsedOuterSpacing)
                .frame(
                    width: collapsedSideExtensionWidth,
                    height: collapsedIndicatorHeight,
                    alignment: .bottomLeading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedAccessibilityLabel)
    }

    private var collapsedAgentLogoLayer: some View {
        HStack(spacing: 0) {
            activeAgentLogo
                .padding(.bottom, collapsedOuterSpacing)
                .frame(
                    width: collapsedSideExtensionWidth,
                    height: collapsedIndicatorHeight,
                    alignment: .bottomTrailing
                )

            Color.clear
                .frame(width: collapsedCenterGapWidth, height: collapsedIndicatorHeight)

            Color.clear
                .frame(width: collapsedSideExtensionWidth, height: collapsedIndicatorHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var renderedAgentActivityState: TerminalAgentActivityState {
        sessionState.isRunning ? sessionState.agentActivityState : .idle
    }

    private var activeAgentLogo: some View {
        ZStack {
            if let activeAgent = sessionState.activeAgent,
               let assetName = activeAgentAssetName(activeAgent) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .id(activeAgent.rawValue)
                    .transition(.opacity)
            }
        }
        .frame(width: IslandMetrics.compactMarkSize, height: IslandMetrics.compactMarkSize)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: sessionState.activeAgent?.rawValue
        )
    }

    private func activeAgentAssetName(_ agent: TerminalAgentActivityAgent) -> String? {
        switch agent {
        case .codex:
            AgentLauncher.codex.assetName
        case .claude:
            AgentLauncher.claude.assetName
        case .unknown:
            nil
        }
    }

    private var collapsedAccessibilityLabel: String {
        let status = AgentStatusIndicatorStyle.style(
            for: renderedAgentActivityState,
            reducesMotion: reduceMotion
        ).label
        guard let activeAgent = sessionState.activeAgent else {
            return status
        }

        let agentName = switch activeAgent {
        case .codex: AgentLauncher.codex.displayName
        case .claude: AgentLauncher.claude.displayName
        case .unknown: ""
        }
        return agentName.isEmpty ? status : "\(agentName), \(status)"
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

    private var collapsedOuterSpacing: CGFloat {
        max(collapsedSideExtensionWidth - IslandMetrics.compactMarkSize, 0)
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
        .padding(.horizontal, IslandMetrics.hoverControlOuterPadding)
        .padding(.bottom, IslandMetrics.hoverControlOuterPadding)
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
            RoseThreeStatusIndicator(
                state: renderedAgentActivityState,
                reducesMotion: reduceMotion
            )

            Text(
                AgentStatusIndicatorStyle.style(
                    for: renderedAgentActivityState,
                    reducesMotion: reduceMotion
                ).label
            )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(height: IslandMetrics.notchControlHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AgentStatusIndicatorStyle.style(
                for: renderedAgentActivityState,
                reducesMotion: reduceMotion
            ).label
        )
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

private struct RoseThreeStatusIndicator: View {
    let state: TerminalAgentActivityState
    let reducesMotion: Bool

    private var style: AgentStatusIndicatorStyle {
        .style(for: state, reducesMotion: reducesMotion)
    }

    private var color: Color {
        switch style.colorRole {
        case .ready:
            Color(nsColor: .systemGreen)
        case .working:
            .primary
        case .waiting:
            Color(nsColor: .systemBlue)
        }
    }

    var body: some View {
        Group {
            if style.animates {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        drawAnimated(in: &context, size: size, date: timeline.date)
                    }
                }
            } else {
                Canvas { context, size in
                    context.stroke(
                        RoseThreeGeometry.path(in: size),
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: IslandMetrics.compactMarkSize, height: IslandMetrics.compactMarkSize)
        .accessibilityHidden(true)
    }

    private func drawAnimated(
        in context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        context.stroke(
            RoseThreeGeometry.path(in: size),
            with: .color(color.opacity(0.12)),
            style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round)
        )

        let headPhase = date.timeIntervalSinceReferenceDate / RoseThreeGeometry.loopDuration
        for index in 0..<RoseThreeGeometry.particleCount {
            let scale = RoseThreeGeometry.particleScale(index: index)
            let diameter = RoseThreeGeometry.maximumParticleDiameter * scale
            let point = RoseThreeGeometry.point(
                at: RoseThreeGeometry.particlePhase(headPhase: headPhase, index: index),
                in: size
            )
            let particle = Path(
                ellipseIn: CGRect(
                    x: point.x - diameter / 2,
                    y: point.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
            context.fill(particle, with: .color(color.opacity(scale)))
        }
    }
}
