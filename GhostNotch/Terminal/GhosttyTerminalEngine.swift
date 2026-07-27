import Foundation

/// Wheel handling on the alternate screen when the app does not use Ghostty mouse reporting.
enum TerminalAlternateScreenScrollPolicy {
    /// Maximum synthesized arrow-key events per wheel tick (avoids flooding the PTY).
    static let maxArrowKeyRepeatsPerWheelTick = 8
}

@MainActor
final class GhosttyTerminalEngine: TerminalRenderingEngine {
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?
    var onAgentStatusEvidenceChange: ((TerminalAgentStatusEvidence) -> Void)?

    private let core: GhosttyTerminalCore
    private let sessionWriter: (TerminalSession?, Data) throws -> Void
    private weak var session: TerminalSession?
    private var cellWidthPixels = 8
    private var cellHeightPixels = 16
    private(set) var lastAppliedGridResize: TerminalGridResize?

    init(
        core: GhosttyTerminalCore = GhosttyTerminalCore(),
        sessionWriter: @escaping (TerminalSession?, Data) throws -> Void = { session, data in
            try session?.write(data)
        }
    ) {
        self.core = core
        self.sessionWriter = sessionWriter
    }

    var snapshot: TerminalRenderSnapshot {
        core.snapshot
    }

    func start(session: TerminalSession) {
        self.session = session
        core.onWriteToPTY = { [weak self] data in
            self?.writeToSession(data)
        }
        publishSnapshot()
    }

    func processOutput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        let previousEvidence = core.agentStatusEvidence
        core.processOutput(data)
        if core.agentStatusEvidence != previousEvidence {
            onAgentStatusEvidenceChange?(core.agentStatusEvidence)
        }
        publishSnapshot()
    }

    func sendInput(_ input: Data) {
        writeToSession(input)
    }

    func sendKeyEvent(_ event: TerminalKeyEvent) {
        sendEncodedKeyEvent(event)
    }

    func handleScrollWheel(_ event: TerminalScrollEvent) {
        guard event.deltaRows != 0 else {
            return
        }

        if core.snapshot.isAlternateScreen {
            handleAlternateScreenScrollWheel(event)
            return
        }

        core.scrollViewport(deltaRows: event.deltaRows)
        publishSnapshot()
    }

    func handleMouseEvent(_ event: TerminalMouseEvent) {
        guard core.snapshot.hasMouseTracking,
              let input = core.encodeMouseEvent(event) else {
            return
        }

        writeToSession(input)
    }

    func resize(cols: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int) {
        let requested = TerminalGridResize.normalized(
            columns: cols,
            rows: rows,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
        if requested == lastAppliedGridResize {
            return
        }

        lastAppliedGridResize = requested
        self.cellWidthPixels = requested.cellWidthPixels
        self.cellHeightPixels = requested.cellHeightPixels
        core.resize(
            columns: requested.columns,
            rows: requested.rows,
            cellWidthPixels: requested.cellWidthPixels,
            cellHeightPixels: requested.cellHeightPixels
        )
        publishSnapshot()

        guard session?.isRunning == true else {
            return
        }

        do {
            try session?.resize(cols: requested.columns, rows: requested.rows)
        } catch {
            NSLog("GhostNotch failed to resize terminal: \(error.localizedDescription)")
        }
    }

    func reset(cols: Int, rows: Int) {
        lastAppliedGridResize = nil
        let requested = TerminalGridResize.normalized(
            columns: cols,
            rows: rows,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
        let previousEvidence = core.agentStatusEvidence
        core.reset(columns: requested.columns, rows: requested.rows)
        core.resize(
            columns: requested.columns,
            rows: requested.rows,
            cellWidthPixels: requested.cellWidthPixels,
            cellHeightPixels: requested.cellHeightPixels
        )
        lastAppliedGridResize = requested
        if core.agentStatusEvidence != previousEvidence {
            onAgentStatusEvidenceChange?(core.agentStatusEvidence)
        }
        publishSnapshot()
    }

    func focus() {
        guard core.snapshot.isFocusReportingMode else {
            return
        }

        writeToSession(core.focusData())
    }

    func blur() {
        guard core.snapshot.isFocusReportingMode else {
            return
        }

        writeToSession(core.blurData())
    }

    private func writeToSession(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        do {
            try sessionWriter(session, data)
        } catch {
            NSLog("GhostNotch failed to write terminal input: \(error.localizedDescription)")
        }
    }

    private func handleAlternateScreenScrollWheel(_ event: TerminalScrollEvent) {
        if core.snapshot.hasMouseTracking,
           let input = core.encodeMouseWheel(column: event.column, row: event.row, deltaRows: event.deltaRows) {
            writeToSession(input)
            return
        }

        let key: TerminalKey = event.deltaRows < 0 ? .arrowUp : .arrowDown
        let repeats = min(abs(event.deltaRows), TerminalAlternateScreenScrollPolicy.maxArrowKeyRepeatsPerWheelTick)
        for _ in 0..<repeats {
            sendEncodedKeyEvent(TerminalKeyEvent(key: key, modifiers: [], utf8: nil, isRepeat: false))
        }
    }

    private func sendEncodedKeyEvent(_ event: TerminalKeyEvent) {
        guard let input = core.encodeKey(event) else {
            return
        }

        writeToSession(input)
    }

    private func publishSnapshot() {
        let snapshot = core.snapshot
        GhostNotchRuntimeMetrics.recordSnapshotPublish(snapshot, skipped: false)
        onSnapshotChange?(snapshot)
    }
}
