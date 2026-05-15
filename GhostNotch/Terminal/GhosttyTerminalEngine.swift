import Foundation

@MainActor
final class GhosttyTerminalEngine: TerminalRenderingEngine {
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

    private let core: GhosttyTerminalCore
    private let sessionWriter: (TerminalSession?, Data) throws -> Void
    private weak var session: TerminalSession?

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

    func resize(cols: Int, rows: Int) {
        core.resize(columns: cols, rows: rows)
        publishSnapshot()

        guard session?.isRunning == true else {
            return
        }

        do {
            try session?.resize(cols: max(cols, 2), rows: max(rows, 1))
        } catch {
            NSLog("GhostNotch failed to resize terminal: \(error.localizedDescription)")
        }
    }

    func reset(cols: Int, rows: Int) {
        core.reset(columns: cols, rows: rows)
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
