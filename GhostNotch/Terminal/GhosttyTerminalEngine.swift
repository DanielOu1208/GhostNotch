import Foundation

/// Wheel handling on the alternate screen when the app does not use Ghostty mouse reporting.
enum TerminalAlternateScreenScrollPolicy {
    /// Maximum synthesized arrow-key events per wheel tick (avoids flooding the PTY).
    static let maxArrowKeyRepeatsPerWheelTick = 8
}

@MainActor
final class GhosttyTerminalEngine: TerminalRenderingEngine {
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

    private let core: GhosttyTerminalCore
    private let sessionWriter: (TerminalSession?, Data) throws -> Void
    private weak var session: TerminalSession?
    private var cellWidthPixels = 8
    private var cellHeightPixels = 16
    private(set) var lastAppliedGridResize: TerminalGridResize?
    private var lastPublishedSnapshotSignature: TerminalRenderSnapshotSignature?

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
        publishSnapshot(force: true)
    }

    func processOutput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        core.processOutput(data)
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
        publishSnapshot(force: true)

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
        core.reset(columns: requested.columns, rows: requested.rows)
        core.resize(
            columns: requested.columns,
            rows: requested.rows,
            cellWidthPixels: requested.cellWidthPixels,
            cellHeightPixels: requested.cellHeightPixels
        )
        lastAppliedGridResize = requested
        publishSnapshot(force: true)
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

    private func publishSnapshot(force: Bool = false) {
        let snapshot = core.snapshot
        let signature = TerminalRenderSnapshotSignature(snapshot)
        guard force || signature != lastPublishedSnapshotSignature else {
            GhostNotchRuntimeMetrics.recordSnapshotPublish(snapshot, skipped: true)
            return
        }

        lastPublishedSnapshotSignature = signature
        GhostNotchRuntimeMetrics.recordSnapshotPublish(snapshot, skipped: false)
        onSnapshotChange?(snapshot)
    }
}

private struct TerminalRenderSnapshotSignature: Equatable {
    let columns: Int
    let rows: Int
    let cursorColumn: Int
    let cursorRow: Int
    let cursorVisible: Bool
    let cursorBlinking: Bool
    let cursorStyle: TerminalCursorStyle
    let isAlternateScreen: Bool
    let hasMouseTracking: Bool
    let isBracketedPasteMode: Bool
    let isFocusReportingMode: Bool
    let currentWorkingDirectory: String?
    let totalRows: Int
    let scrollbackRows: Int
    let dirtyState: TerminalRenderDirtyState
    let dirtyRows: Set<Int>

    init(_ snapshot: TerminalRenderSnapshot) {
        columns = snapshot.columns
        rows = snapshot.rows
        cursorColumn = snapshot.cursorColumn
        cursorRow = snapshot.cursorRow
        cursorVisible = snapshot.cursorVisible
        cursorBlinking = snapshot.cursorBlinking
        cursorStyle = snapshot.cursorStyle
        isAlternateScreen = snapshot.isAlternateScreen
        hasMouseTracking = snapshot.hasMouseTracking
        isBracketedPasteMode = snapshot.isBracketedPasteMode
        isFocusReportingMode = snapshot.isFocusReportingMode
        currentWorkingDirectory = snapshot.currentWorkingDirectory
        totalRows = snapshot.totalRows
        scrollbackRows = snapshot.scrollbackRows
        dirtyState = snapshot.dirtyState
        dirtyRows = snapshot.dirtyRows
    }
}
