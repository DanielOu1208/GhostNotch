import Foundation

@MainActor
final class TerminalSurfaceCoordinator {
    let session: TerminalSession
    let engine: TerminalRenderingEngine

    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

    private var pendingOutput = Data()
    private var isOutputFlushScheduled = false

    init(
        session: TerminalSession = TerminalSession(),
        engine: TerminalRenderingEngine = GhosttyTerminalEngine()
    ) {
        self.session = session
        self.engine = engine

        engine.start(session: session)
        engine.onSnapshotChange = { [weak self] snapshot in
            self?.session.state.updateWorkingDirectory(snapshot.currentWorkingDirectory)
            self?.onSnapshotChange?(snapshot)
        }
        session.addOutputObserver { [weak self] data in
            self?.enqueueOutput(data)
        }
    }

    var state: TerminalSessionState {
        session.state
    }

    var snapshot: TerminalRenderSnapshot {
        engine.snapshot
    }

    var lastAppliedGridResize: TerminalGridResize? {
        engine.lastAppliedGridResize
    }

    var isRunning: Bool {
        session.isRunning
    }

    func startIfNeeded(cols: Int = 80, rows: Int = 18) {
        guard !session.isRunning else {
            return
        }

        do {
            try session.start(cols: cols, rows: rows)
        } catch {
            NSLog("GhostNotch failed to start terminal session: \(error.localizedDescription)")
        }
    }

    func stop() {
        session.stop()
    }

    func sendInput(_ data: Data) {
        engine.sendInput(data)
    }

    func sendKeyEvent(_ event: TerminalKeyEvent) {
        engine.sendKeyEvent(event)
    }

    func handleScrollWheel(_ event: TerminalScrollEvent) {
        engine.handleScrollWheel(event)
    }

    func handleMouseEvent(_ event: TerminalMouseEvent) {
        engine.handleMouseEvent(event)
    }

    func resize(_ resize: TerminalGridResize) {
        engine.resize(
            cols: resize.columns,
            rows: resize.rows,
            cellWidthPixels: resize.cellWidthPixels,
            cellHeightPixels: resize.cellHeightPixels
        )
    }

    func restartPreservingGrid(currentSnapshot: TerminalRenderSnapshot) {
        let resize = lastAppliedGridResize ?? TerminalGridResize.normalized(
            columns: currentSnapshot.columns,
            rows: currentSnapshot.rows,
            cellWidthPixels: 8,
            cellHeightPixels: 16
        )

        engine.reset(cols: resize.columns, rows: resize.rows)

        do {
            try session.restart(cols: resize.columns, rows: resize.rows)
        } catch {
            NSLog("GhostNotch failed to restart terminal session: \(error.localizedDescription)")
        }
    }

    func focus() {
        engine.focus()
    }

    func blur() {
        engine.blur()
    }

    func currentSnapshot() -> TerminalRenderSnapshot {
        engine.snapshot
    }

    func flushPendingOutputForTesting() {
        flushPendingOutput()
    }

    private func enqueueOutput(_ data: Data) {
        pendingOutput.append(data)
        guard !isOutputFlushScheduled else {
            return
        }

        isOutputFlushScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.flushPendingOutput()
        }
    }

    private func flushPendingOutput() {
        guard !pendingOutput.isEmpty else {
            isOutputFlushScheduled = false
            return
        }

        let output = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        isOutputFlushScheduled = false
        GhostNotchRuntimeMetrics.recordOutputFlush(byteCount: output.count)
        engine.processOutput(output)
    }
}
