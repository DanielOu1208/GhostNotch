import Foundation

@MainActor
final class GhosttyTerminalEngine: TerminalRenderingEngine {
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?

    private let core: GhosttyTerminalCore
    private weak var session: TerminalSession?

    init(core: GhosttyTerminalCore = GhosttyTerminalCore()) {
        self.core = core
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

    func focus() {
        // The core exposes focus encoding for the eventual libghostty-vt bridge.
        // GhostNotch still reserves Escape for collapse, so focus reporting is not forced on programs yet.
        _ = core.focusData()
    }

    func blur() {
        _ = core.blurData()
    }

    private func writeToSession(_ data: Data) {
        do {
            try session?.write(data)
        } catch {
            NSLog("GhostNotch failed to write terminal input: \(error.localizedDescription)")
        }
    }

    private func publishSnapshot() {
        onSnapshotChange?(core.snapshot)
    }
}
