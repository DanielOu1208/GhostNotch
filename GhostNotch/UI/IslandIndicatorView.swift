import AppKit
import SwiftUI

struct IslandIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var sessionState: TerminalSessionState
    @ObservedObject var presetStore: AgentPresetStore
    @Namespace private var directorySelectionNamespace
    @Namespace private var agentSelectionNamespace
    @State private var isPrimaryActionHovering = false

    let isHovering: Bool
    let selectedDirectoryPresetID: AgentLaunchDirectoryPreset.ID?
    let selectedAgentID: AgentLauncher.ID?
    let onSelectDirectory: (AgentLaunchDirectoryPreset) -> Void
    let onSelectAgent: (AgentLauncher) -> Void
    let onPrimaryAction: () -> Void
    let onReset: () -> Void

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
        .onChange(of: isHovering) { _, isHovering in
            if !isHovering {
                isPrimaryActionHovering = false
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
            removal: .opacity.animation(collapsedExitAnimation)
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

        return ZStack(alignment: .topTrailing) {
            if isPrimaryActionHovering {
                LinearGradient(
                    colors: [.clear, .primary.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            VStack(spacing: IslandMetrics.hoverPrimaryActionSpacing) {
                HStack(alignment: .bottom, spacing: IslandMetrics.hoverControlGroupSpacing) {
                    hoverControlGroup("Folders") {
                        directoryPresetControls(directoryPresets)
                    }

                    hoverControlGroup("Agents") {
                        agentControls(enabledLaunchers)
                    }

                    hoverControlGroup("Status") {
                        hoverStatus
                    }
                }

                hoverPrimaryAction
            }
            .padding(.horizontal, IslandMetrics.hoverControlOuterPadding)
            .padding(.bottom, IslandMetrics.hoverPrimaryActionBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            if sessionState.isRunning {
                hoverResetButton
                    .padding(.top, 2)
                    .padding(.trailing, IslandMetrics.hoverControlOuterPadding)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: isPrimaryActionHovering
        )
    }

    private func hoverControlGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: IslandMetrics.hoverControlLabelSpacing) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: IslandMetrics.hoverControlLabelHeight)

            content()
        }
        .frame(width: IslandMetrics.notchCapsuleGroupWidth)
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
        let segmentWidth = IslandMetrics.notchSegmentWidth(itemCount: directoryPresets.count)

        return ZStack {
            if !reduceTransparency {
                selectionLayer(
                    ids: directoryPresets.map(\.id),
                    selectedID: selectedDirectoryPresetID,
                    namespace: directorySelectionNamespace,
                    effectID: "directory-selection",
                    segmentWidth: segmentWidth,
                    usesOpaqueGlass: false
                )
                    .padding(IslandMetrics.notchCapsuleGroupInset)
            }

            HStack(alignment: .center, spacing: 0) {
                ForEach(directoryPresets) { preset in
                    DirectoryPresetButton(
                        preset: preset,
                        isSelected: preset.id == selectedDirectoryPresetID,
                        selectionColor: directorySelectionColor,
                        selectionNamespace: directorySelectionNamespace,
                        selectionTransition: directorySelectionTransition,
                        width: segmentWidth
                    ) {
                        onSelectDirectory(preset)
                    }
                }
            }
            .frame(width: IslandMetrics.notchCapsuleContentWidth)
            .background {
                if reduceTransparency {
                    selectionLayer(
                        ids: directoryPresets.map(\.id),
                        selectedID: selectedDirectoryPresetID,
                        namespace: directorySelectionNamespace,
                        effectID: "directory-selection",
                        segmentWidth: segmentWidth,
                        usesOpaqueGlass: true
                    )
                }
            }
            .notchCapsuleGroupStyle()
        }
        .animation(directorySelectionAnimation, value: selectedDirectoryPresetID)
    }

    private func selectionLayer<ID: Hashable>(
        ids: [ID],
        selectedID: ID?,
        namespace: Namespace.ID,
        effectID: String,
        segmentWidth: CGFloat,
        usesOpaqueGlass: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                ZStack {
                    if id == selectedID {
                        selectionCapsule(
                            width: segmentWidth,
                            usesOpaqueGlass: usesOpaqueGlass
                        )
                            .matchedGeometryEffect(
                                id: usesOpaqueGlass ? "opaque-\(effectID)" : effectID,
                                in: namespace
                            )
                            .transition(directorySelectionTransition)
                    }
                }
                .frame(width: segmentWidth, height: IslandMetrics.notchControlHeight)
            }
        }
        .frame(width: IslandMetrics.notchCapsuleContentWidth)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionCapsule(width: CGFloat, usesOpaqueGlass: Bool) -> some View {
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
            width: width + IslandMetrics.notchSelectionBackingExtraWidth,
            height: IslandMetrics.notchControlHeight
                + IslandMetrics.notchSelectionBackingExtraHeight
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

    private func agentControls(_ launchers: [AgentLauncher]) -> some View {
        let segmentWidth = IslandMetrics.notchSegmentWidth(itemCount: launchers.count)

        return ZStack {
            if !reduceTransparency {
                selectionLayer(
                    ids: launchers.map(\.id),
                    selectedID: selectedAgentID,
                    namespace: agentSelectionNamespace,
                    effectID: "agent-selection",
                    segmentWidth: segmentWidth,
                    usesOpaqueGlass: false
                )
                .padding(IslandMetrics.notchCapsuleGroupInset)
            }

            HStack(alignment: .center, spacing: 0) {
                ForEach(launchers) { launcher in
                    AgentLauncherButton(
                        launcher: launcher,
                        isSelected: launcher.id == selectedAgentID,
                        selectionColor: directorySelectionColor,
                        selectionNamespace: agentSelectionNamespace,
                        selectionTransition: directorySelectionTransition,
                        width: segmentWidth
                    ) {
                        onSelectAgent(launcher)
                    }
                }
            }
            .frame(width: IslandMetrics.notchCapsuleContentWidth)
            .background {
                if reduceTransparency {
                    selectionLayer(
                        ids: launchers.map(\.id),
                        selectedID: selectedAgentID,
                        namespace: agentSelectionNamespace,
                        effectID: "agent-selection",
                        segmentWidth: segmentWidth,
                        usesOpaqueGlass: true
                    )
                }
            }
            .notchCapsuleGroupStyle()
        }
        .animation(directorySelectionAnimation, value: selectedAgentID)
    }

    private var hoverStatus: some View {
        HStack(alignment: .center, spacing: 4) {
            RoseThreeStatusIndicator(
                state: renderedAgentActivityState,
                reducesMotion: reduceMotion
            )

            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(
            width: IslandMetrics.notchCapsuleContentWidth,
            height: IslandMetrics.notchControlHeight
        )
        .notchCapsuleGroupStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLabel)
    }

    private var hoverPrimaryAction: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 4) {
                Text(primaryActionTitle)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(isPrimaryActionHovering ? 1 : 0.72))
            .frame(
                width: IslandMetrics.hoverPrimaryActionWidth,
                height: IslandMetrics.hoverPrimaryActionHeight
            )
            .contentShape(Rectangle())
        }
        .frame(
            width: IslandMetrics.hoverPrimaryActionWidth,
            height: IslandMetrics.hoverPrimaryActionHeight
        )
        .buttonStyle(.plain)
        .onHover { isPrimaryActionHovering = $0 }
        .accessibilityLabel(primaryActionTitle)
        .help(primaryActionHelp)
    }

    private var hoverResetButton: some View {
        Button(action: onReset) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: IslandMetrics.notchControlWidth,
                    height: IslandMetrics.notchControlHeight
                )
                .contentShape(Capsule())
        }
        .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
        .notchControlStyle()
        .notchCapsuleGroupStyle()
        .accessibilityLabel("Restart terminal and clear launch selections")
        .help("Restart terminal and clear launch selections")
    }

    private var statusLabel: String {
        statusStyle.label
    }

    private var statusStyle: AgentStatusIndicatorStyle {
        AgentStatusIndicatorStyle.style(
            for: renderedAgentActivityState,
            reducesMotion: reduceMotion
        )
    }

    private var selectedLauncher: AgentLauncher? {
        presetStore.enabledLaunchers.first { $0.id == selectedAgentID }
    }

    private var primaryActionTitle: String {
        primaryAction.title(
            agentName: primaryActionAgentName,
            directoryName: selectedDirectoryName
        )
    }

    private var primaryAction: HoverPrimaryAction {
        HoverPrimaryAction.resolve(
            selectedAgentID: selectedAgentID,
            enabledAgentIDs: presetStore.enabledAgentIDs
        )
    }

    private var primaryActionAgentName: String? {
        switch primaryAction {
        case .expand:
            guard sessionState.isRunning else {
                return nil
            }
            return activeAgentDisplayName
        case .launch:
            return selectedLauncher?.displayName
        }
    }

    private var activeAgentDisplayName: String? {
        switch sessionState.activeAgent {
        case .codex:
            AgentLauncher.codex.displayName
        case .claude:
            AgentLauncher.claude.displayName
        case .unknown, nil:
            nil
        }
    }

    private var selectedDirectoryName: String? {
        visibleDirectoryPresets
            .first { $0.id == selectedDirectoryPresetID }?
            .displayLabel
    }

    private var primaryActionHelp: String {
        primaryActionTitle
    }
}

private struct DirectoryPresetButton: View {
    let preset: AgentLaunchDirectoryPreset
    let isSelected: Bool
    let selectionColor: Color
    let selectionNamespace: Namespace.ID
    let selectionTransition: AnyTransition
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(selectionColor)
                        .frame(
                            width: width
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
            .frame(width: width, height: IslandMetrics.notchControlHeight)
            .contentShape(Capsule())
        }
        .frame(width: width, height: IslandMetrics.notchControlHeight)
        .notchControlStyle(width: width)
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
    let isSelected: Bool
    let selectionColor: Color
    let selectionNamespace: Namespace.ID
    let selectionTransition: AnyTransition
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(selectionColor)
                        .frame(
                            width: width
                                - IslandMetrics.notchCapsuleGroupInset * 2,
                            height: IslandMetrics.notchControlHeight
                                - IslandMetrics.notchCapsuleGroupInset * 2
                        )
                        .matchedGeometryEffect(
                            id: "foreground-agent-selection",
                            in: selectionNamespace
                        )
                        .transition(selectionTransition)
                }

                Image(launcher.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 17, height: 17)
            }
            .frame(width: width, height: IslandMetrics.notchControlHeight)
            .contentShape(Capsule())
        }
        .frame(width: width, height: IslandMetrics.notchControlHeight)
        .notchControlStyle(width: width)
        .accessibilityLabel("\(isSelected ? "Deselect" : "Select") \(launcher.displayName)")
        .help("\(isSelected ? "Deselect" : "Select") \(launcher.displayName)")
    }
}

private struct RoseThreeStatusIndicator: View {
    let state: TerminalAgentActivityState
    let reducesMotion: Bool

    private var style: AgentStatusIndicatorStyle {
        .style(for: state, reducesMotion: reducesMotion)
    }

    private var color: Color {
        style.colorRole.color
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
            with: .color(color.opacity(RoseThreeGeometry.activeGuideOpacity)),
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

private extension AgentStatusIndicatorStyle.ColorRole {
    var color: Color {
        switch self {
        case .ready:
            Color(nsColor: .systemGreen)
        case .working:
            .primary
        case .waiting:
            Color(nsColor: .systemBlue)
        }
    }
}
