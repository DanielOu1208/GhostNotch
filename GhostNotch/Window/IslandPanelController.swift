import AppKit
import QuartzCore
import SwiftUI

private struct PanelFrameAnimation {
    let plan: IslandTransitionPlan
    let generation: Int
    let startFrame: NSRect
    let targetFrame: NSRect
    let screenFrame: NSRect
    let startTime: TimeInterval
}

@MainActor
final class IslandPanelController: ObservableObject {
    @Published private(set) var state: IslandState = .collapsed
    @Published private(set) var notchFillMode: NotchFillMode = .black
    @Published private(set) var terminalFocusRequestID = 0
    @Published private(set) var terminalSurfaceRepaintRequestID = 0
    @Published private(set) var terminalSnapshot = TerminalRenderSnapshot.empty()
    @Published private(set) var terminalSurfacePhase: IslandTerminalSurfacePhase = .idle
    @Published private(set) var selectedLaunchDirectoryPresetID: AgentLaunchDirectoryPreset.ID?
    @Published private(set) var transitionPlan: IslandTransitionPlan?
    @Published private(set) var compactContentVisible = true
    @Published private(set) var expandedHeaderVisible = false
    @Published private(set) var expandedTerminalVisible = false

    var allowsGridResizeReporting: Bool {
        terminalSurfacePhase == .ready
    }

    var showsCompactContent: Bool {
        state != .expanded || transitionPlan.map { $0.from != .expanded } == true
    }

    var showsExpandedContent: Bool {
        state == .expanded || transitionPlan?.from == .expanded
    }

    var compactPresentationState: IslandState {
        if state == .expanded, let transitionPlan, transitionPlan.from != .expanded {
            return transitionPlan.from
        }

        return state
    }

    var expandedContentIsInteractive: Bool {
        terminalSurfacePhase == .ready && transitionPlan == nil
    }

    let agentPresetStore: AgentPresetStore

    private let panel: IslandPanel
    private let terminalSurfaceCoordinator: TerminalSurfaceCoordinator
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingAgentLaunchTask: Task<Void, Never>?
    private var pendingHoverExitTask: Task<Void, Never>?
    private var pendingReducedMotionCompletionTask: Task<Void, Never>?
    private var pendingTransitionStartTask: Task<Void, Never>?
    private var panelDisplayLink: CADisplayLink?
    private var panelFrameAnimation: PanelFrameAnimation?
    private var lastHoverContainment: Bool?
    private var applicationBeforeGhostNotch: NSRunningApplication?
    private var transitionGeneration = 0
    private lazy var outsideClickMonitor = OutsideClickMonitor(
        shouldCollapse: { [weak self] in self?.state == .expanded },
        isPointInsidePanel: { [weak self] point in self?.panel.frame.contains(point) ?? false },
        collapse: { [weak self] in self?.collapse() }
    )

    var terminalState: TerminalSessionState {
        terminalSurfaceCoordinator.state
    }

    var lastAppliedGridResize: TerminalGridResize? {
        terminalSurfaceCoordinator.lastAppliedGridResize
    }

    init(
        terminalSession: TerminalSession = TerminalSession(),
        terminalEngine: TerminalRenderingEngine = GhosttyTerminalEngine(),
        agentPresetStore: AgentPresetStore = .shared
    ) {
        self.agentPresetStore = agentPresetStore
        terminalSurfaceCoordinator = TerminalSurfaceCoordinator(
            session: terminalSession,
            engine: terminalEngine
        )

        panel = IslandPanel(
            contentRect: WindowPositioner.frame(for: .collapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        terminalSurfaceCoordinator.onSnapshotChange = { [weak self] snapshot in
            guard let self, self.showsExpandedContent else {
                return
            }

            self.terminalSnapshot = snapshot
        }

        configurePanel()

        let rootView = IslandRootView(
            onClick: { [weak self] in self?.expand() }
        )

        let hostingView = NSHostingView(rootView: rootView.environmentObject(self))
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        panel.onEscape = { [weak self] in self?.collapse() }
    }

    func show() {
        outsideClickMonitor.start()
        startHoverMonitoring()
        panel.orderFrontRegardless()
    }

    func tearDown() {
        pendingAgentLaunchTask?.cancel()
        pendingHoverExitTask?.cancel()
        pendingReducedMotionCompletionTask?.cancel()
        pendingTransitionStartTask?.cancel()
        pendingTransitionStartTask = nil
        stopPanelFrameAnimation()
        restorePreviousApplication()
        outsideClickMonitor.stop()
        stopHoverMonitoring()
        terminalSurfaceCoordinator.stop()
        panel.close()
    }

    func expand() {
        expand(startTerminal: true)
    }

    func launchAgent(_ launcher: AgentLauncher) {
        pendingAgentLaunchTask?.cancel()

        expand(startTerminal: false)
        let launchSnapshot = terminalSurfaceCoordinator.currentSnapshot()
        let directoryPath = selectedLaunchDirectoryPath()
        selectedLaunchDirectoryPresetID = nil

        pendingAgentLaunchTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.terminalSurfaceCoordinator.launchAgent(
                launcher,
                currentSnapshot: launchSnapshot,
                directoryPath: directoryPath
            )
        }
    }

    func selectLaunchDirectory(_ preset: AgentLaunchDirectoryPreset) {
        guard preset.directoryExists() else {
            return
        }

        selectedLaunchDirectoryPresetID = DirectoryPresetSelection.toggled(
            currentSelection: selectedLaunchDirectoryPresetID,
            selectedPresetID: preset.id
        )
    }

    private func expand(startTerminal: Bool) {
        if state == .expanded {
            if transitionPlan == nil {
                activateTerminalSurface()
            }
            return
        }

        terminalSurfacePhase = .expanding
        captureApplicationBeforeActivation()
        panel.shouldAcceptKeyFocus = true
        panel.styleMask.remove(.nonactivatingPanel)
        NSApp.activate()
        if startTerminal {
            startTerminalIfNeeded()
        }
        transition(to: .expanded)
        panel.makeKeyAndOrderFront(nil)
    }

    func collapse() {
        guard state != .collapsed else {
            return
        }

        pendingHoverExitTask?.cancel()
        let destination: IslandState = if state == .expanded {
            IslandTransitionPlan.closeDestination(
                pointer: NSEvent.mouseLocation,
                hoverFrame: WindowPositioner.frame(for: .hover)
            )
        } else {
            .collapsed
        }

        terminalSurfacePhase = .idle
        panel.shouldAcceptKeyFocus = destination == .hover
        if destination == .collapsed {
            panel.resignKey()
            panel.styleMask.insert(.nonactivatingPanel)
        }
        if shouldSendBlurOnCollapse() {
            terminalSurfaceCoordinator.blur()
        }
        transition(to: destination)
    }

    func toggleNotchFillMode() {
        notchFillMode.toggle()
    }

    func writeToTerminal(_ data: Data) {
        terminalSurfaceCoordinator.sendInput(data)
    }

    func sendTerminalKeyEvent(_ event: TerminalKeyEvent) {
        terminalSurfaceCoordinator.sendKeyEvent(event)
    }

    func handleTerminalScrollWheel(_ event: TerminalScrollEvent) {
        terminalSurfaceCoordinator.handleScrollWheel(event)
    }

    func handleTerminalMouseEvent(_ event: TerminalMouseEvent) {
        terminalSurfaceCoordinator.handleMouseEvent(event)
    }

    func resizeTerminal(cols: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int) {
        let resize = TerminalGridResize.normalized(
            columns: cols,
            rows: rows,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
        terminalSurfaceCoordinator.resize(resize)
    }

    func restartTerminal() {
        terminalSurfaceCoordinator.restartPreservingGrid(currentSnapshot: terminalSurfaceCoordinator.currentSnapshot())
        activateTerminalSurface()
    }

    private func startHoverMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.refreshHoverState()
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard Thread.isMainThread else {
                DispatchQueue.main.async {
                    self?.refreshHoverState()
                }
                return
            }
            self?.refreshHoverState()
        }
    }

    private func stopHoverMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func refreshHoverState() {
        guard state != .expanded, transitionPlan?.from != .expanded else {
            return
        }

        let isHovering = WindowPositioner.containsHoverPoint(
            NSEvent.mouseLocation,
            in: panel.frame
        )
        guard lastHoverContainment != isHovering else {
            GhostNotchRuntimeMetrics.recordHoverEvent(stateChanged: false)
            return
        }

        lastHoverContainment = isHovering
        GhostNotchRuntimeMetrics.recordHoverEvent(stateChanged: true)
        setHovering(isHovering)
    }

    private func setHovering(_ isHovering: Bool) {
        guard state != .expanded else {
            return
        }

        if isHovering {
            pendingHoverExitTask?.cancel()
            guard state != .hover else {
                return
            }
            activateHoverPanel()
            transition(to: .hover)
        } else {
            guard state == .hover else {
                return
            }
            scheduleHoverExit()
        }
    }

    private func scheduleHoverExit() {
        pendingHoverExitTask?.cancel()
        pendingHoverExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(IslandTransitionPlan.hoverExitGrace * 1_000_000_000)
                )
            } catch {
                return
            }

            guard let self,
                  self.state == .hover,
                  !WindowPositioner.containsHoverPoint(
                      NSEvent.mouseLocation,
                      in: WindowPositioner.frame(for: .hover)
                  )
            else {
                return
            }

            self.transition(to: .collapsed)
        }
    }

    private func activateHoverPanel() {
        captureApplicationBeforeActivation()

        panel.shouldAcceptKeyFocus = true
        panel.styleMask.remove(.nonactivatingPanel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func deactivateHoverPanel() {
        panel.shouldAcceptKeyFocus = false
        panel.resignKey()
        panel.styleMask.insert(.nonactivatingPanel)
        restorePreviousApplication()
    }

    private func restorePreviousApplication() {
        let application = applicationBeforeGhostNotch
        applicationBeforeGhostNotch = nil

        guard NSApp.isActive, let application, !application.isTerminated else {
            return
        }

        application.activate()
    }

    private func captureApplicationBeforeActivation() {
        guard applicationBeforeGhostNotch == nil,
              let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        applicationBeforeGhostNotch = frontmostApplication
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
    }

    private func startTerminalIfNeeded() {
        terminalSurfaceCoordinator.startIfNeeded()
    }

    private func selectedLaunchDirectoryPath() -> String? {
        guard let selectedLaunchDirectoryPresetID,
              let preset = agentPresetStore.directoryPresets.first(where: { $0.id == selectedLaunchDirectoryPresetID }),
              preset.directoryExists() else {
            return nil
        }

        return preset.path
    }

    private func activateTerminalSurface() {
        terminalSnapshot = terminalSurfaceCoordinator.currentSnapshot()
        requestTerminalSurfaceRepaint()
        requestTerminalFocus()
        terminalSurfaceCoordinator.focus()
    }

    private func requestTerminalFocus() {
        terminalFocusRequestID += 1
    }

    private func requestTerminalSurfaceRepaint() {
        terminalSurfaceRepaintRequestID += 1
    }

    private func transition(to newState: IslandState) {
        guard state != newState else {
            return
        }

        pendingReducedMotionCompletionTask?.cancel()
        pendingTransitionStartTask?.cancel()
        pendingTransitionStartTask = nil
        stopPanelFrameAnimation()
        transitionGeneration += 1
        let generation = transitionGeneration
        let plan = IslandTransitionPlan(
            from: state,
            to: newState,
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        transitionPlan = plan

        state = newState
        if newState == .expanded {
            terminalSnapshot = terminalSurfaceCoordinator.currentSnapshot()
            lastHoverContainment = nil
        } else if newState == .hover {
            lastHoverContainment = true
        } else {
            lastHoverContainment = false
        }

        guard plan.requiresLayoutStaging else {
            animateContent(for: plan)
            animatePanel(for: plan, generation: generation)
            return
        }

        pendingTransitionStartTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  plan.canComplete(
                    generation: generation,
                    currentGeneration: self.transitionGeneration,
                    state: self.state
                  )
            else {
                return
            }

            self.animateContent(for: plan)
            self.animatePanel(for: plan, generation: generation)
        }
    }

    private func animateContent(for plan: IslandTransitionPlan) {
        if plan.reducesMotion {
            withAnimation(.easeOut(duration: plan.duration)) {
                compactContentVisible = plan.to != .expanded
                expandedHeaderVisible = plan.to == .expanded
                expandedTerminalVisible = plan.to == .expanded
            }
            return
        }

        if plan.to == .expanded {
            withAnimation(
                .easeOut(
                    duration: plan.duration * IslandTransitionPlan.outgoingContentDurationFraction
                )
            ) {
                compactContentVisible = false
            }
            let primaryContentDelay = plan.duration
                * IslandTransitionPlan.primaryContentEntryDelayFraction
            withAnimation(
                .easeOut(duration: plan.duration - primaryContentDelay)
                    .delay(primaryContentDelay)
            ) {
                expandedHeaderVisible = true
            }
            withAnimation(
                .easeOut(duration: plan.duration * 0.65)
                    .delay(plan.duration * 0.35)
            ) {
                expandedTerminalVisible = true
            }
            return
        }

        if plan.from == .expanded {
            withAnimation(.easeOut(duration: plan.duration * 0.35)) {
                expandedTerminalVisible = false
            }
            withAnimation(.easeOut(duration: plan.duration * 0.45)) {
                expandedHeaderVisible = false
            }
            withAnimation(
                .easeOut(duration: plan.duration * 0.25)
                    .delay(plan.duration * 0.75)
            ) {
                compactContentVisible = true
            }
        }
    }

    private func animatePanel(for plan: IslandTransitionPlan, generation: Int) {
        let screen = WindowPositioner.notchScreen
        let targetFrame = WindowPositioner.frame(for: plan.to, on: screen)

        if plan.reducesMotion {
            panel.setFrame(targetFrame, display: true)
            pendingReducedMotionCompletionTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(plan.duration * 1_000_000_000))
                } catch {
                    return
                }
                self?.completeTransition(plan, generation: generation)
            }
            return
        }

        let startFrame = WindowPositioner.transitionFrame(
            from: panel.frame,
            to: targetFrame,
            progress: 0,
            screenFrame: screen.frame
        )
        panel.setFrame(startFrame, display: true)
        panelFrameAnimation = PanelFrameAnimation(
            plan: plan,
            generation: generation,
            startFrame: startFrame,
            targetFrame: targetFrame,
            screenFrame: screen.frame,
            startTime: CACurrentMediaTime()
        )

        let displayLink = panel.displayLink(target: self, selector: #selector(advancePanelAnimation(_:)))
        panelDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func advancePanelAnimation(_ displayLink: CADisplayLink) {
        guard displayLink === panelDisplayLink, let animation = panelFrameAnimation else {
            return
        }

        let elapsedTime = max(displayLink.targetTimestamp - animation.startTime, 0)
        let frame = WindowPositioner.transitionFrame(
            from: animation.startFrame,
            to: animation.targetFrame,
            progress: animation.plan.progress(at: elapsedTime),
            screenFrame: animation.screenFrame
        )
        panel.setFrame(frame, display: true)

        guard elapsedTime >= animation.plan.duration else {
            return
        }

        panel.setFrame(animation.targetFrame, display: true)
        stopPanelFrameAnimation()
        completeTransition(animation.plan, generation: animation.generation)
    }

    private func stopPanelFrameAnimation() {
        panelDisplayLink?.invalidate()
        panelDisplayLink = nil
        panelFrameAnimation = nil
    }

    private func completeTransition(_ plan: IslandTransitionPlan, generation: Int) {
        guard plan.canComplete(
            generation: generation,
            currentGeneration: transitionGeneration,
            state: state
        ) else {
            return
        }

        transitionPlan = nil
        switch plan.to {
        case .expanded:
            finishExpandPanelAnimation()
        case .hover:
            if plan.from == .expanded {
                lastHoverContainment = nil
                refreshHoverState()
            }
        case .collapsed:
            deactivateHoverPanel()
        }
    }

    private func finishExpandPanelAnimation() {
        guard state == .expanded else {
            return
        }

        terminalSurfacePhase = .ready
        activateTerminalSurface()
    }

    private func shouldSendBlurOnCollapse() -> Bool {
        !terminalSurfaceCoordinator.currentSnapshot().isAlternateScreen
    }
}
