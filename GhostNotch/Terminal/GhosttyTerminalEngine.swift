import Foundation

@MainActor
final class GhosttyTerminalEngine: TerminalRenderingEngine {
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

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
        core.processOutput(data)
        publishSnapshot()
    }

    func sendInput(_ input: Data) {
        writeToSession(input)
    }

    func sendKeyEvent(_ event: TerminalKeyEvent) {
        guard let input = core.encodeKey(event) else {
            return
        }

        writeToSession(input)
    }

    func scrollViewport(deltaRows: Int) {
        core.scrollViewport(deltaRows: deltaRows)
        publishSnapshot()
    }

    func resize(cols: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int) {
        let requested = TerminalGridResize(
            columns: max(cols, 2),
            rows: max(rows, 1),
            cellWidthPixels: max(cellWidthPixels, 1),
            cellHeightPixels: max(cellHeightPixels, 1)
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
        let columns = max(cols, 2)
        let rowCount = max(rows, 1)
        core.reset(columns: columns, rows: rowCount)
        core.resize(
            columns: columns,
            rows: rowCount,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
        lastAppliedGridResize = TerminalGridResize(
            columns: columns,
            rows: rowCount,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
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

    private func publishSnapshot() {
        onSnapshotChange?(core.snapshot)
    }
}
