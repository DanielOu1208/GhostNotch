import XCTest
import AppKit

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

    func testExtendedSgrStyleMetadataRendering() {
        let core = GhosttyTerminalCore(columns: 48, rows: 2)

        core.processOutput(Data("\u{1B}[2;5;8;9;53;4:3;58:2:12:34:56mstyled".utf8))

        let style = core.snapshot.cell(row: 0, column: 0).style
        XCTAssertTrue(style.isFaint)
        XCTAssertTrue(style.isBlinking)
        XCTAssertTrue(style.isInvisible)
        XCTAssertTrue(style.isStrikethrough)
        XCTAssertTrue(style.isOverline)
        XCTAssertEqual(style.underlineStyle, .curly)
        XCTAssertEqual(style.underlineColor, TerminalColor(red: 12, green: 34, blue: 56))
    }

    func testUnderlineStyleVariantsArePreserved() {
        let streams: [(String, TerminalUnderlineStyle)] = [
            ("\u{1B}[4mA", .single),
            ("\u{1B}[4:2mA", .double),
            ("\u{1B}[4:3mA", .curly),
            ("\u{1B}[4:4mA", .dotted),
            ("\u{1B}[4:5mA", .dashed),
        ]

        for (stream, expectedStyle) in streams {
            let snapshot = renderFixture(stream, columns: 4, rows: 1)
            XCTAssertEqual(snapshot.cell(row: 0, column: 0).style.underlineStyle, expectedStyle)
        }
    }

    func testColorFidelityPreservesAnsi256AndTruecolorCells() {
        let snapshot = renderFixture(
            "\u{1B}[38;5;196;48;5;24mA\u{1B}[38;2;1;2;3;48;2;4;5;6mB",
            columns: 4,
            rows: 1
        )

        XCTAssertEqual(snapshot.cell(row: 0, column: 0).style.foreground, TerminalColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(snapshot.cell(row: 0, column: 0).style.background, TerminalColor(red: 0, green: 95, blue: 135))
        XCTAssertEqual(snapshot.cell(row: 0, column: 1).style.foreground, TerminalColor(red: 1, green: 2, blue: 3))
        XCTAssertEqual(snapshot.cell(row: 0, column: 1).style.background, TerminalColor(red: 4, green: 5, blue: 6))
    }

    func testInversePreservesExtendedDecorations() {
        let snapshot = renderFixture("\u{1B}[7;9;53;4:2mA", columns: 4, rows: 1)
        let style = snapshot.cell(row: 0, column: 0).style

        XCTAssertTrue(style.isInverse)
        XCTAssertTrue(style.isStrikethrough)
        XCTAssertTrue(style.isOverline)
        XCTAssertEqual(style.underlineStyle, .double)
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

    func testResetClearsVisibleCellsPreservesDimensionsAndWriteCallback() {
        let core = GhosttyTerminalCore(columns: 5, rows: 2)
        var written = Data()
        core.onWriteToPTY = { data in
            written.append(data)
        }

        core.processOutput(Data("abc".utf8))
        core.reset(columns: 9, rows: 4)

        XCTAssertEqual(core.snapshot.columns, 9)
        XCTAssertEqual(core.snapshot.rows, 4)
        XCTAssertFalse(core.snapshot.plainText.contains("abc"))

        core.processOutput(Data("\u{1B}[c".utf8))
        XCTAssertEqual(written, Data("\u{1B}[?62;22c".utf8))
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

    func testBracketedPasteModeTracksTerminalModeState() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)

        XCTAssertFalse(core.snapshot.isBracketedPasteMode)

        core.processOutput(Data("\u{1B}[?2004h".utf8))
        XCTAssertTrue(core.snapshot.isBracketedPasteMode)

        core.processOutput(Data("\u{1B}[?2004l".utf8))
        XCTAssertFalse(core.snapshot.isBracketedPasteMode)
    }

    func testFocusReportingModeTracksTerminalModeState() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)

        XCTAssertFalse(core.snapshot.isFocusReportingMode)

        core.processOutput(Data("\u{1B}[?1004h".utf8))
        XCTAssertTrue(core.snapshot.isFocusReportingMode)

        core.processOutput(Data("\u{1B}[?1004l".utf8))
        XCTAssertFalse(core.snapshot.isFocusReportingMode)
    }

    func testFocusAndBlurEncoding() {
        let core = GhosttyTerminalCore()

        XCTAssertEqual(core.focusData(), Data("\u{1B}[I".utf8))
        XCTAssertEqual(core.blurData(), Data("\u{1B}[O".utf8))
    }

    func testEngineSendsFocusEventsOnlyWhenModeIsEnabled() {
        let core = GhosttyTerminalCore(columns: 8, rows: 2)
        var writes: [Data] = []
        let engine = GhosttyTerminalEngine(core: core) { _, data in
            writes.append(data)
        }

        engine.focus()
        engine.blur()
        XCTAssertTrue(writes.isEmpty)

        engine.processOutput(Data("\u{1B}[?1004h".utf8))
        engine.focus()
        engine.blur()
        XCTAssertEqual(writes, [
            Data("\u{1B}[I".utf8),
            Data("\u{1B}[O".utf8),
        ])

        engine.processOutput(Data("\u{1B}[?1004l".utf8))
        engine.focus()
        engine.blur()
        XCTAssertEqual(writes.count, 2)
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

    func testBlockElementFillRectsUseExpectedFractions() {
        let rect = NSRect(x: 0, y: 0, width: 16, height: 16)

        XCTAssertEqual(
            TerminalCellGlyphRenderer.blockFillRects(for: "▃", in: rect, scale: 2),
            [TerminalGlyphFill(rect: NSRect(x: 0, y: 10, width: 16, height: 6), alpha: 1)]
        )
        XCTAssertEqual(
            TerminalCellGlyphRenderer.blockFillRects(for: "▊", in: rect, scale: 2),
            [TerminalGlyphFill(rect: NSRect(x: 0, y: 0, width: 12, height: 16), alpha: 1)]
        )
        XCTAssertEqual(
            TerminalCellGlyphRenderer.blockFillRects(for: "▚", in: rect, scale: 2),
            [
                TerminalGlyphFill(rect: NSRect(x: 0, y: 0, width: 8, height: 8), alpha: 1),
                TerminalGlyphFill(rect: NSRect(x: 8, y: 8, width: 8, height: 8), alpha: 1),
            ]
        )
    }

    func testBoxDrawingStrokesTouchCellEdgesAndAlignToPixels() {
        let rect = NSRect(x: 0, y: 0, width: 14, height: 14)

        let lightHorizontal = TerminalCellGlyphRenderer.boxStrokeRects(for: "─", in: rect, scale: 2)
        XCTAssertEqual(lightHorizontal?.first?.minX, 0)
        XCTAssertEqual(lightHorizontal?.last?.maxX, 14)
        XCTAssertEqual(lightHorizontal?.first?.height, 1)

        let corner = TerminalCellGlyphRenderer.boxStrokeRects(for: "┌", in: rect, scale: 2) ?? []
        XCTAssertTrue(corner.contains { rect in
            rect.minX == 6.5 && rect.minY == 7 && rect.maxY == 14
        })
        XCTAssertTrue(corner.contains { rect in
            rect.minX == 7 && rect.maxX == 14 && rect.minY == 6.5
        })
    }

    func testDecorationRectsArePixelAlignedAtOneAndTwoXScale() {
        let rect = NSRect(x: 0, y: 0, width: 12, height: 14)
        let style = TerminalCellStyle(
            foreground: .foreground,
            background: .background,
            underlineColor: nil,
            isBold: false,
            isItalic: false,
            isFaint: false,
            isBlinking: false,
            isInverse: false,
            isInvisible: false,
            isStrikethrough: true,
            isOverline: true,
            underlineStyle: .double
        )

        for scale in [CGFloat(1), CGFloat(2)] {
            let rects = TerminalTextDecorationRenderer.decorationRects(style: style, in: rect, scale: scale)
            XCTAssertEqual(rects.count, 4)
            for decorationRect in rects {
                XCTAssertEqual((decorationRect.minY * scale).rounded(), decorationRect.minY * scale)
                XCTAssertEqual((decorationRect.height * scale).rounded(), decorationRect.height * scale)
            }
        }
    }

    func testPowerlineFallbackScopeIsLimitedToCommonSeparators() {
        XCTAssertEqual(
            TerminalCellGlyphRenderer.powerlineFallbackCharacters(),
            Set(["\u{E0B0}", "\u{E0B1}", "\u{E0B2}", "\u{E0B3}"])
        )
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
            isBracketedPasteMode: false,
            isFocusReportingMode: false,
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
