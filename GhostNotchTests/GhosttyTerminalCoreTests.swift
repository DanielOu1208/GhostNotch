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

    func testCombiningGraphemeClustersArePreserved() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)
        let grapheme = "e\u{0301}"

        core.processOutput(Data("\u{1B}[?2027h\(grapheme)x".utf8))

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, grapheme)
        XCTAssertEqual(snapshot.cell(row: 0, column: 1).character, "x")
        XCTAssertTrue(snapshot.plainText.contains("\(grapheme)x"))
    }

    func testEmojiGraphemesArePreservedInSnapshotText() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)

        core.processOutput(Data("🙂x".utf8))

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, "🙂")
        XCTAssertTrue(snapshot.plainText.contains("🙂x"))
    }

    func testWideCharactersUseSpacerCellsWithoutDuplicatingCopiedText() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)

        core.processOutput(Data("界x".utf8))

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, "界")
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).widthRole, .wideHead)
        XCTAssertEqual(snapshot.cell(row: 0, column: 1).widthRole, .wideSpacerTail)
        XCTAssertEqual(snapshot.cell(row: 0, column: 2).character, "x")
        XCTAssertEqual(
            snapshot.text(in: TerminalSelection(start: TerminalGridPoint(row: 0, column: 0), end: TerminalGridPoint(row: 0, column: 2))),
            "界x"
        )
    }

    func testPrivateUsePromptGlyphsFlowThrough() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)
        let glyph = "\u{E0B0}"

        core.processOutput(Data("\(glyph)x".utf8))

        let snapshot = core.snapshot
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).character, glyph)
        XCTAssertTrue(snapshot.plainText.contains("\(glyph)x"))
    }

    func testPlainTextPreservesLeadingIndentation() {
        let core = GhosttyTerminalCore(columns: 12, rows: 2)

        core.processOutput(Data("  indented".utf8))

        XCTAssertTrue(core.snapshot.plainText.hasPrefix("  indented"))
    }

    func testSelectionPreservesInternalAndNarrowTrailingSpaces() {
        let snapshot = makeSnapshot(rowText: "a  b  ", columns: 8)

        XCTAssertEqual(
            snapshot.text(in: TerminalSelection(start: TerminalGridPoint(row: 0, column: 0), end: TerminalGridPoint(row: 0, column: 2))),
            "a  "
        )
        XCTAssertEqual(
            snapshot.text(in: TerminalSelection(start: TerminalGridPoint(row: 0, column: 0), end: TerminalGridPoint(row: 0, column: 3))),
            "a  b"
        )
    }

    func testSelectionTrimsOnlyRightEdgeGridPadding() {
        let snapshot = makeSnapshot(rowText: "a       ", columns: 8)

        XCTAssertEqual(
            snapshot.text(in: TerminalSelection(start: TerminalGridPoint(row: 0, column: 0), end: TerminalGridPoint(row: 0, column: 7))),
            "a"
        )
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

        XCTAssertEqual(written, Data("\u{1B}[?62;22c".utf8))
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

    func testGhosttyKeyEncodingHandlesEscapeAndArrows() {
        let core = GhosttyTerminalCore()

        XCTAssertEqual(
            core.encodeKey(TerminalKeyEvent(key: .escape, modifiers: [], utf8: nil, isRepeat: false)),
            Data("\u{1B}".utf8)
        )
        XCTAssertEqual(
            core.encodeKey(TerminalKeyEvent(key: .arrowUp, modifiers: [], utf8: nil, isRepeat: false)),
            Data("\u{1B}[A".utf8)
        )
    }

    func testGhosttyKeyEncodingUsesModifierAwareControlInput() {
        let core = GhosttyTerminalCore()

        XCTAssertEqual(
            core.encodeKey(TerminalKeyEvent(key: .letter("c"), modifiers: [.control], utf8: "c", isRepeat: false)),
            Data([0x03])
        )
    }

    func testScrollbackViewportUsesGhosttyState() {
        let core = GhosttyTerminalCore(columns: 12, rows: 3)
        core.processOutput(Data((0..<12).map { "line\($0)" }.joined(separator: "\n").utf8))
        let bottomText = core.snapshot.plainText

        XCTAssertGreaterThan(core.snapshot.scrollbackRows, 0)

        core.scrollViewport(deltaRows: -2)

        XCTAssertNotEqual(core.snapshot.plainText, bottomText)
        XCTAssertGreaterThan(core.snapshot.scrollbackRows, 0)
    }

    func testCursorStyleMetadataComesFromGhosttyRenderState() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)

        core.processOutput(Data("\u{1B}[2 q".utf8))

        XCTAssertEqual(core.snapshot.cursorStyle, .block)
    }

    func testRendererAcceptanceFixtureStreamsProtectCoreModel() {
        let styled = renderFixture("plain\r\n\u{1B}[31;1mred\u{1B}[0m", columns: 12, rows: 3)
        XCTAssertTrue(styled.plainText.contains("plain"))
        XCTAssertEqual(styled.cell(row: 1, column: 0).character, "r")
        XCTAssertEqual(styled.cell(row: 1, column: 0).style.foreground, .ansi(index: 1))
        XCTAssertTrue(styled.cell(row: 1, column: 0).style.isBold)

        let cursorMovement = renderFixture("abc\u{1B}[1;2HZ", columns: 8, rows: 2)
        XCTAssertEqual(cursorMovement.cell(row: 0, column: 0).character, "a")
        XCTAssertEqual(cursorMovement.cell(row: 0, column: 1).character, "Z")
        XCTAssertEqual(cursorMovement.cell(row: 0, column: 2).character, "c")

        let unicode = renderFixture("\u{1B}[?2027he\u{0301} 🙂 界 \u{E0B0}", columns: 12, rows: 2)
        XCTAssertEqual(unicode.cell(row: 0, column: 0).character, "e\u{0301}")
        XCTAssertTrue(unicode.plainText.contains("🙂"))
        XCTAssertEqual(unicode.cell(row: 0, column: 5).character, "界")
        XCTAssertEqual(unicode.cell(row: 0, column: 5).widthRole, .wideHead)
        XCTAssertEqual(unicode.cell(row: 0, column: 6).widthRole, .wideSpacerTail)
        XCTAssertTrue(unicode.plainText.contains("\u{E0B0}"))

        let wideCopy = renderFixture("wide: |界|x|", columns: 16, rows: 2)
        XCTAssertEqual(
            wideCopy.text(in: TerminalSelection(start: TerminalGridPoint(row: 0, column: 6), end: TerminalGridPoint(row: 0, column: 10))),
            "|界|x"
        )

        let alternateScreen = renderFixture("primary\u{1B}[?1049halt\u{1B}[2Jalt\u{1B}[?1049l", columns: 12, rows: 3)
        XCTAssertFalse(alternateScreen.isAlternateScreen)
        XCTAssertTrue(alternateScreen.plainText.contains("primary"))
        XCTAssertFalse(alternateScreen.plainText.contains("alt"))

        let scrollback = GhosttyTerminalCore(columns: 12, rows: 3)
        scrollback.processOutput(Data((0..<12).map { "line\($0)" }.joined(separator: "\n").utf8))
        let bottomText = scrollback.snapshot.plainText
        scrollback.scrollViewport(deltaRows: -2)
        XCTAssertGreaterThan(scrollback.snapshot.scrollbackRows, 0)
        XCTAssertNotEqual(scrollback.snapshot.plainText, bottomText)
    }

    private func makeSnapshot(rowText: String, columns: Int) -> TerminalRenderSnapshot {
        let cells = Array(rowText.padding(toLength: columns, withPad: " ", startingAt: 0).prefix(columns)).map {
            TerminalCell(character: String($0), style: .default, widthRole: .narrow)
        }
        return TerminalRenderSnapshot(
            columns: columns,
            rows: 1,
            cells: cells,
            cursorColumn: 0,
            cursorRow: 0,
            cursorVisible: true,
            cursorBlinking: false,
            cursorStyle: .bar,
            isAlternateScreen: false,
            hasMouseTracking: false,
            totalRows: 1,
            scrollbackRows: 0
        )
    }

    private func renderFixture(_ stream: String, columns: Int, rows: Int) -> TerminalRenderSnapshot {
        let core = GhosttyTerminalCore(columns: columns, rows: rows)
        core.processOutput(Data(stream.utf8))
        return core.snapshot
    }
}
