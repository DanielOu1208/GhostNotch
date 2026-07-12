import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: ObservableObject {
    @Published private(set) var state: IslandState = .collapsed
    @Published private(set) var notchFillMode: NotchFillMode = .black
    @Published private(set) var terminalFocusRequestID = 0
    @Published private(set) var terminalSurfaceRepaintRequestID = 0
    @Published private(set) var terminalSnapshot = TerminalRenderSnapshot.empty()
    @Published private(set) var terminalSurfacePhase: IslandTerminalSurfacePhase = .idle
    @Published private(set) var selectedLaunchDirectoryPresetID: AgentLaunchDirectoryPreset.ID?

    var allowsGridResizeReporting: Bool {
        terminalSurfacePhase == .ready
    }

    let agentPresetStore: AgentPresetStore

    private let panel: IslandPanel
    private let terminalSurfaceCoordinator: TerminalSurfaceCoordinator
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingAgentLaunchTask: Task<Void, Never>?
    private var lastHoverContainment: Bool?
    private var applicationBeforeHover: NSRunningApplication?
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
            self?.terminalSnapshot = snapshot
        }

        configurePanel()

        let rootView = IslandRootView(
            onClick: { [weak self] in self?.expand() }
        )

        panel.contentView = IslandHostingView(rootView: rootView.environmentObject(self))
        panel.onEscape = { [weak self] in self?.collapse() }
    }

    func show() {
        outsideClickMonitor.start()
        startHoverMonitoring()
        panel.orderFrontRegardless()
    }

    func tearDown() {
        pendingAgentLaunchTask?.cancel()
        restoreApplicationAfterHover()
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
            activateTerminalSurface()
            return
        }

        terminalSurfacePhase = .expanding
        applicationBeforeHover = nil
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

        terminalSurfacePhase = .idle
        panel.shouldAcceptKeyFocus = false
        panel.resignKey()
        panel.styleMask.insert(.nonactivatingPanel)
        if shouldSendBlurOnCollapse() {
            terminalSurfaceCoordinator.blur()
        }
        transition(to: .collapsed)
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
        guard state != .expanded else {
            return
        }

        let isHovering = panel.frame.contains(NSEvent.mouseLocation)
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

        guard state != (isHovering ? .hover : .collapsed) else {
            return
        }

        if isHovering {
            activateHoverPanel()
            transition(to: .hover)
        } else {
            transition(to: .collapsed)
            deactivateHoverPanel()
        }
    }

    private func activateHoverPanel() {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            applicationBeforeHover = frontmostApplication
        }

        panel.shouldAcceptKeyFocus = true
        panel.styleMask.remove(.nonactivatingPanel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func deactivateHoverPanel() {
        panel.shouldAcceptKeyFocus = false
        panel.resignKey()
        panel.styleMask.insert(.nonactivatingPanel)
        restoreApplicationAfterHover()
    }

    private func restoreApplicationAfterHover() {
        let application = applicationBeforeHover
        applicationBeforeHover = nil

        guard NSApp.isActive, let application, !application.isTerminated else {
            return
        }

        application.activate()
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
        state = newState
        if newState == .expanded {
            lastHoverContainment = nil
        }
        animatePanel(to: newState)
    }

    private func animatePanel(to newState: IslandState) {
        let frame = WindowPositioner.frame(for: newState)
        let shouldFinishExpandAfterAnimation = newState == .expanded

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = newState == .expanded ? 0.18 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: {
            guard shouldFinishExpandAfterAnimation else {
                return
            }
            Task { @MainActor in
                self.finishExpandPanelAnimation()
            }
        })
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
