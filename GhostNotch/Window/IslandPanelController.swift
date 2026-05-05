import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: ObservableObject {
    @Published private(set) var state: IslandState = .collapsed
    @Published private(set) var notchFillMode: NotchFillMode = .black
    @Published private(set) var terminalFocusRequestID = 0

    private let panel: IslandPanel
    private let terminalSession: TerminalSession
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private lazy var outsideClickMonitor = OutsideClickMonitor(
        shouldCollapse: { [weak self] in self?.state == .expanded },
        isPointInsidePanel: { [weak self] point in self?.panel.frame.contains(point) ?? false },
        collapse: { [weak self] in self?.collapse() }
    )

    var terminalState: TerminalSessionState {
        terminalSession.state
    }

    init(terminalSession: TerminalSession = TerminalSession()) {
        self.terminalSession = terminalSession

        panel = IslandPanel(
            contentRect: WindowPositioner.frame(for: .collapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

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
        outsideClickMonitor.stop()
        stopHoverMonitoring()
        terminalSession.stop()
        panel.close()
    }

    func expand() {
        if state == .expanded {
            requestTerminalFocus()
            return
        }

        panel.shouldAcceptKeyFocus = true
        panel.styleMask.remove(.nonactivatingPanel)
        NSApp.activate()
        startTerminalIfNeeded()
        transition(to: .expanded)
        panel.makeKeyAndOrderFront(nil)
        requestTerminalFocus()
    }

    func collapse() {
        guard state != .collapsed else {
            return
        }

        panel.shouldAcceptKeyFocus = false
        panel.resignKey()
        panel.styleMask.insert(.nonactivatingPanel)
        transition(to: .collapsed)
    }

    func toggleNotchFillMode() {
        notchFillMode.toggle()
    }

    func writeToTerminal(_ data: Data) {
        do {
            try terminalSession.write(data)
        } catch {
            NSLog("GhostNotch failed to write terminal input: \(error.localizedDescription)")
        }
    }

    func resizeTerminal(cols: Int, rows: Int) {
        guard terminalSession.isRunning else {
            return
        }

        do {
            try terminalSession.resize(cols: max(cols, 2), rows: max(rows, 1))
        } catch {
            NSLog("GhostNotch failed to resize terminal: \(error.localizedDescription)")
        }
    }

    private func startHoverMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.refreshHoverState()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHoverState()
            }
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

        setHovering(panel.frame.contains(NSEvent.mouseLocation))
    }

    private func setHovering(_ isHovering: Bool) {
        guard state != .expanded else {
            return
        }

        guard state != (isHovering ? .hover : .collapsed) else {
            return
        }

        transition(to: isHovering ? .hover : .collapsed)
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
        guard !terminalSession.isRunning else {
            return
        }

        do {
            try terminalSession.start(cols: 80, rows: 18)
        } catch {
            NSLog("GhostNotch failed to start terminal session: \(error.localizedDescription)")
        }
    }

    private func requestTerminalFocus() {
        terminalFocusRequestID += 1
    }

    private func transition(to newState: IslandState) {
        state = newState
        animatePanel(to: newState)
    }

    private func animatePanel(to newState: IslandState) {
        let frame = WindowPositioner.frame(for: newState)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = newState == .expanded ? 0.16 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}
