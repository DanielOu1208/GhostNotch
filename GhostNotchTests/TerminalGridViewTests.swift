import AppKit
import XCTest

@MainActor
final class TerminalGridViewTests: XCTestCase {
    func testTerminalGridSurfaceActivationForcesFullRedrawForCleanSnapshot() {
        var invalidations: [(fullRedraw: Bool, rowCount: Int)] = []
        GhostNotchRuntimeMetrics.gridInvalidationRecorder = { fullRedraw, rowCount in
            invalidations.append((fullRedraw, rowCount))
        }
        defer {
            GhostNotchRuntimeMetrics.gridInvalidationRecorder = nil
        }

        let view = TerminalGridView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
        view.updateSnapshot(cleanTerminalSnapshot())

        view.invalidateRowsFromSnapshot()
        view.forceFullRedrawForSurfaceActivation()

        XCTAssertEqual(invalidations.map(\.fullRedraw), [false, true])
        XCTAssertEqual(invalidations.map(\.rowCount), [0, 3])
    }

    private func cleanTerminalSnapshot() -> TerminalRenderSnapshot {
        TerminalRenderSnapshot(
            columns: 8,
            rows: 3,
            cells: Array(repeating: .blank, count: 24),
            cursorColumn: 0,
            cursorRow: 0,
            cursorVisible: false,
            cursorBlinking: false,
            cursorStyle: .bar,
            isAlternateScreen: false,
            hasMouseTracking: false,
            isBracketedPasteMode: false,
            isFocusReportingMode: false,
            currentWorkingDirectory: nil,
            totalRows: 3,
            scrollbackRows: 0,
            dirtyState: .clean,
            dirtyRows: []
        )
    }
}
