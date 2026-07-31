import Foundation

@MainActor
final class TerminalSurfaceCoordinator {
    let session: TerminalSession
    let engine: TerminalRenderingEngine

    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

    private var pendingOutput = Data()
    private var isOutputFlushScheduled = false
    private var outputEpoch: UInt64 = 0
    private let agentLaunchReadinessPollNanoseconds: UInt64 = 10_000_000

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
        engine.onAgentStatusEvidenceChange = { [weak self] evidence in
            self?.session.state.updateAgentStatusEvidence(evidence)
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

    func startIfNeeded(cols: Int = 80, rows: Int = 18, workingDirectory: String? = nil) {
        guard !session.isRunning else {
            return
        }

        do {
            try session.start(cols: cols, rows: rows, workingDirectory: workingDirectory)
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

    func restartPreservingGrid(currentSnapshot: TerminalRenderSnapshot, workingDirectory: String? = nil) {
        let resize = lastAppliedGridResize ?? TerminalGridResize.normalized(
            columns: currentSnapshot.columns,
            rows: currentSnapshot.rows,
            cellWidthPixels: 8,
            cellHeightPixels: 16
        )

        outputEpoch &+= 1
        pendingOutput.removeAll(keepingCapacity: true)
        isOutputFlushScheduled = false
        engine.reset(cols: resize.columns, rows: resize.rows)

        do {
            try session.restart(cols: resize.columns, rows: resize.rows, workingDirectory: workingDirectory)
        } catch {
            NSLog("GhostNotch failed to restart terminal session: \(error.localizedDescription)")
        }
    }

    func launchAgent(
        _ launcher: AgentLauncher,
        currentSnapshot: TerminalRenderSnapshot,
        directoryPath: String? = nil,
        startupTimeout: TimeInterval = TerminalSession.defaultStartupTimeout
    ) async {
        startFreshSessionForAgentLaunch(
            currentSnapshot: currentSnapshot,
            workingDirectory: directoryPath
        )

        guard await waitForRunningSession(timeout: startupTimeout) else {
            return
        }

        guard !Task.isCancelled else {
            return
        }

        sendInput(Data(launcher.commandLine.utf8))
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
        flushPendingOutput(epoch: outputEpoch)
    }

    private func startFreshSessionForAgentLaunch(
        currentSnapshot: TerminalRenderSnapshot,
        workingDirectory: String?
    ) {
        if session.isRunning || session.state.hasReceivedOutput || session.state.phase == .failed {
            restartPreservingGrid(
                currentSnapshot: currentSnapshot,
                workingDirectory: workingDirectory
            )
        } else {
            startIfNeeded(workingDirectory: workingDirectory)
        }
    }

    private func waitForRunningSession(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if Task.isCancelled {
                return false
            }

            switch session.state.phase {
            case .running:
                return true
            case .failed, .stopped:
                return false
            case .starting:
                break
            }

            do {
                try await Task.sleep(nanoseconds: agentLaunchReadinessPollNanoseconds)
            } catch {
                return false
            }
        }

        return session.state.phase == .running && !Task.isCancelled
    }

    private func enqueueOutput(_ data: Data) {
        pendingOutput.append(data)
        guard !isOutputFlushScheduled else {
            return
        }

        isOutputFlushScheduled = true
        let epoch = outputEpoch
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.flushPendingOutput(epoch: epoch)
        }
    }

    private func flushPendingOutput(epoch: UInt64) {
        guard epoch == outputEpoch else {
            return
        }
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
