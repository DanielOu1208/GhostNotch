import XCTest

@MainActor
final class GhosttyTerminalCoreTests: XCTestCase {
    func testAnsiColorAndStyleRendering() {
        let core = GhosttyTerminalCore(columns: 20, rows: 3)

        core.processOutput(Data("\u{1B}[31;1mred\u{1B}[0m plain".utf8))

        let snapshot = core.snapshot
        let red = snapshot.cell(row: 0, column: 0)
        let plain = snapshot.cell(row: 0, column: 4)

        XCTAssertEqual(red.character, "r")
        XCTAssertTrue(red.style.isBold)
        XCTAssertEqual(red.style.foreground, .ansi(index: 1))
        XCTAssertEqual(plain.character, "p")
        XCTAssertFalse(plain.style.isBold)
        XCTAssertEqual(plain.style.foreground, .foreground)
    }

    func testCursorPositioningAndLineClearing() {
        let core = GhosttyTerminalCore(columns: 8, rows: 3)

        core.processOutput(Data("abcdef\u{1B}[1;3HZZ\u{1B}[K".utf8))

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, "a")
        XCTAssertEqual(snapshot.cell(row: 0, column: 1).character, "b")
        XCTAssertEqual(snapshot.cell(row: 0, column: 2).character, "Z")
        XCTAssertEqual(snapshot.cell(row: 0, column: 3).character, "Z")
        XCTAssertEqual(snapshot.cell(row: 0, column: 4).character, " ")
    }

    func testAlternateScreenEnterAndExitPreservesPrimaryScreen() {
        let core = GhosttyTerminalCore(columns: 12, rows: 3)

        core.processOutput(Data("primary\u{1B}[?1049halt\u{1B}[2Jalt\u{1B}[?1049l".utf8))

        let snapshot = core.snapshot
        XCTAssertFalse(snapshot.isAlternateScreen)
        XCTAssertTrue(snapshot.plainText.contains("primary"))
        XCTAssertFalse(snapshot.plainText.contains("alt"))
    }

    func testResizePreservesVisibleCellsAndUpdatesDimensions() {
        let core = GhosttyTerminalCore(columns: 5, rows: 2)

        core.processOutput(Data("abc".utf8))
        core.resize(columns: 8, rows: 4)

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.columns, 8)
        XCTAssertEqual(snapshot.rows, 4)
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, "a")
        XCTAssertEqual(snapshot.cell(row: 0, column: 2).character, "c")
    }

    func testDeviceQueryWritesBackToPTY() {
        let core = GhosttyTerminalCore(columns: 10, rows: 2)
        var written = Data()
        core.onWriteToPTY = { data in
            written.append(data)
        }

        core.processOutput(Data("\u{1B}[c".utf8))

        XCTAssertEqual(written, Data("\u{1B}[?62;c".utf8))
    }

    func testPasteEncodingUsesBracketedPasteAndRemovesEscape() {
        let input = "echo hi\u{1B}\n"
        let data = GhosttyTerminalCore.encodePaste(input)

        XCTAssertEqual(data, Data("\u{1B}[200~echo hi \n\u{1B}[201~".utf8))
    }

    func testFocusAndBlurEncoding() {
        let core = GhosttyTerminalCore()

        XCTAssertEqual(core.focusData(), Data("\u{1B}[I".utf8))
        XCTAssertEqual(core.blurData(), Data("\u{1B}[O".utf8))
    }
}
