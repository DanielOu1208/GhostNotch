import AppKit

final class TerminalGridView: NSView {
    var snapshot = TerminalRenderSnapshot.empty()
    var onInput: ((Data) -> Void)?
    var onKeyEvent: ((TerminalKeyEvent) -> Void)?
    var onScroll: ((TerminalScrollEvent) -> Void)?
    var onMouseEvent: ((TerminalMouseEvent) -> Void)?
    var onResize: ((Int, Int, Int, Int) -> Void)?
    var onMovedToWindow: (() -> Void)?
    var allowsResizeReporting = true

    private let typography = TerminalGridTypography(size: TerminalGridMetrics.fontSize)
    var lastReportedResize: TerminalGridResize?
    private var selection: TerminalSelection?
    private var previousCursorRowForInvalidation: Int?
    private var colorCache: [TerminalColor: NSColor] = [:]

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let cellSize = measuredCellSize
        let rowRange = visibleRowRange(in: dirtyRect, cellSize: cellSize)
        for row in rowRange {
            for column in 0..<snapshot.columns {
                drawCell(snapshot.cell(row: row, column: column), row: row, column: column, cellSize: cellSize)
            }
        }

        if snapshot.cursorVisible, rowRange.contains(snapshot.cursorRow) {
            drawCursor(cellSize: cellSize)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            if event.keyCode == 9 {
                paste(nil)
                return
            }

            if event.keyCode == 8 {
                copy(nil)
                return
            }

            super.keyDown(with: event)
            return
        }

        guard let keyEvent = TerminalKeyEvent(event: event) else {
            return
        }

        onKeyEvent?(keyEvent)
    }

    @objc func paste(_ sender: Any?) {
        guard let pastedText = NSPasteboard.general.string(forType: .string),
              let input = TerminalInputMapping.data(forPastedText: pastedText, bracketed: snapshot.isBracketedPasteMode) else {
            return
        }

        onInput?(input)
    }

    @objc func copy(_ sender: Any?) {
        guard let selection else {
            return
        }

        let selectedText = snapshot.text(in: selection)
        guard !selectedText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    override func scrollWheel(with event: NSEvent) {
        let cellSize = measuredCellSize
        let preciseRows = -event.scrollingDeltaY / max(cellSize.height, 1)
        let rowDelta = Int(preciseRows.rounded())
        guard rowDelta != 0 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let gridPoint = gridPoint(at: point) ?? TerminalGridPoint(
            row: max(0, min(snapshot.cursorRow, snapshot.rows - 1)),
            column: max(0, min(snapshot.cursorColumn, snapshot.columns - 1))
        )
        onScroll?(TerminalScrollEvent(deltaRows: rowDelta, row: gridPoint.row, column: gridPoint.column))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard !snapshot.hasMouseTracking else {
            selection = nil
            sendMouseEvent(.press, button: .left, from: event, anyButtonPressed: true)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let gridPoint = gridPoint(at: point) else {
            selection = nil
            needsDisplay = true
            return
        }

        selection = TerminalSelection(start: gridPoint, end: gridPoint)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !snapshot.hasMouseTracking else {
            selection = nil
            sendMouseEvent(.motion, button: .left, from: event, anyButtonPressed: true)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let gridPoint = gridPoint(at: point),
              let currentSelection = selection else {
            return
        }

        selection = TerminalSelection(start: currentSelection.start, end: gridPoint)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard snapshot.hasMouseTracking else {
            super.mouseUp(with: event)
            return
        }

        sendMouseEvent(.release, button: .left, from: event, anyButtonPressed: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportSizeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportSizeIfNeeded()
        onMovedToWindow?()
    }

    func reportSizeIfNeeded() {
        guard allowsResizeReporting else {
            return
        }

        let visibleSize = bounds.size
        guard visibleSize.width > 0, visibleSize.height > 0 else {
            return
        }

        let cellSize = measuredCellSize
        let inset = TerminalGridMetrics.contentInset
        let measuredColumns = Int(floor((visibleSize.width - inset * 2) / cellSize.width))
        let measuredRows = Int(floor((visibleSize.height - inset * 2) / cellSize.height))
        let cellPixelSize = measuredCellPixelSize
        let resize = TerminalGridResize.normalized(
            columns: measuredColumns,
            rows: measuredRows,
            cellWidthPixels: cellPixelSize.width,
            cellHeightPixels: cellPixelSize.height
        )

        guard resize != lastReportedResize else {
            return
        }

        selection = nil
        lastReportedResize = resize
        onResize?(resize.columns, resize.rows, resize.cellWidthPixels, resize.cellHeightPixels)
    }

    func updateSnapshot(_ newSnapshot: TerminalRenderSnapshot) {
        clearSelectionIfNeeded(for: newSnapshot)
        snapshot = newSnapshot
    }

    func invalidateRowsFromSnapshot() {
        guard !snapshot.needsFullRedraw else {
            previousCursorRowForInvalidation = snapshot.cursorVisible ? snapshot.cursorRow : nil
            GhostNotchRuntimeMetrics.recordGridInvalidation(fullRedraw: true, rowCount: snapshot.rows)
            needsDisplay = true
            return
        }

        let cellSize = measuredCellSize
        let rowsToInvalidate = snapshot.rowsNeedingDisplay(previousCursorRow: previousCursorRowForInvalidation)
        previousCursorRowForInvalidation = snapshot.cursorVisible ? snapshot.cursorRow : nil
        GhostNotchRuntimeMetrics.recordGridInvalidation(fullRedraw: false, rowCount: rowsToInvalidate.count)
        for row in rowsToInvalidate {
            setNeedsDisplay(rowRect(row: row, cellSize: cellSize))
        }
    }

    private var measuredCellSize: NSSize {
        typography.cellSize
    }

    private var measuredCellPixelSize: (width: Int, height: Int) {
        let scale = backingScale
        return (
            width: max(1, Int((measuredCellSize.width * scale).rounded())),
            height: max(1, Int((measuredCellSize.height * scale).rounded()))
        )
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? layer?.contentsScale ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    private func drawCell(_ cell: TerminalCell, row: Int, column: Int, cellSize: NSSize) {
        let inset = TerminalGridMetrics.contentInset
        let rect = NSRect(
            x: CGFloat(column) * cellSize.width + inset,
            y: CGFloat(row) * cellSize.height + inset,
            width: cellSize.width,
            height: cellSize.height
        )
        let textRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: cell.widthRole == .wideHead && column + 1 < snapshot.columns ? cellSize.width * 2 : cellSize.width,
            height: cellSize.height
        )

        let style = cell.style
        let foreground = style.isInverse ? style.background : style.foreground
        let background = style.isInverse ? style.foreground : style.background
        let hasSelection = selection?.contains(row: row, column: column) == true
        let hasVisibleGlyph = cell.hasVisibleGlyph
        let hasDecoration = style.hasTextDecoration

        if !hasSelection,
           background == .background,
           (!hasVisibleGlyph || cell.widthRole.isSpacer || style.isInvisible),
           !hasDecoration {
            return
        }

        if hasSelection {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
            rect.fill()
        } else if background != .background {
            cachedColor(for: background).setFill()
            rect.fill()
        }

        guard !cell.widthRole.isSpacer, !style.isInvisible else {
            return
        }

        let resolvedForeground = cachedColor(for: foreground).withAlphaComponent(style.isFaint ? 0.5 : 0.92)
        if hasVisibleGlyph {
            let didDrawTerminalGlyph = TerminalCellGlyphRenderer.draw(
                cell.character,
                foreground: resolvedForeground,
                in: textRect,
                scale: backingScale,
                fontSupportsText: typography.supports(cell.character)
            )

            if !didDrawTerminalGlyph {
                typography.draw(
                    cell.character,
                    style: style,
                    foreground: resolvedForeground,
                    in: textRect,
                    viewHeight: bounds.height
                )
            }
        }

        if hasDecoration {
            TerminalTextDecorationRenderer.draw(
                style: style,
                foreground: resolvedForeground,
                in: textRect,
                scale: backingScale
            )
        }
    }

    private func drawCursor(cellSize: NSSize) {
        guard snapshot.cursorVisible else {
            return
        }

        let rect: NSRect
        switch snapshot.cursorStyle {
        case .bar:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + TerminalGridMetrics.contentInset,
                y: CGFloat(snapshot.cursorRow) * cellSize.height + TerminalGridMetrics.contentInset,
                width: 1.5,
                height: cellSize.height
            )
        case .block, .hollowBlock:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + TerminalGridMetrics.contentInset,
                y: CGFloat(snapshot.cursorRow) * cellSize.height + TerminalGridMetrics.contentInset,
                width: cellSize.width,
                height: cellSize.height
            )
        case .underline:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + TerminalGridMetrics.contentInset,
                y: CGFloat(snapshot.cursorRow + 1) * cellSize.height + TerminalGridMetrics.contentInset - 2,
                width: cellSize.width,
                height: 1.5
            )
        }

        cachedColor(for: .cursor).withAlphaComponent(0.9).setFill()
        if snapshot.cursorStyle == .hollowBlock {
            rect.frame(withWidth: 1.2)
        } else {
            rect.fill()
        }
    }

    private func visibleRowRange(in dirtyRect: NSRect, cellSize: NSSize) -> Range<Int> {
        let inset = TerminalGridMetrics.contentInset
        let startRow = max(0, Int(floor((dirtyRect.minY - inset) / max(cellSize.height, 1))))
        let endRow = min(
            snapshot.rows,
            Int(ceil((dirtyRect.maxY - inset) / max(cellSize.height, 1))) + 1
        )
        guard startRow < endRow else {
            return 0..<0
        }
        return startRow..<endRow
    }

    private func rowRect(row: Int, cellSize: NSSize) -> NSRect {
        NSRect(
            x: 0,
            y: CGFloat(row) * cellSize.height + TerminalGridMetrics.contentInset,
            width: bounds.width,
            height: cellSize.height
        )
    }

    private func sendMouseEvent(
        _ action: TerminalMouseEventAction,
        button: TerminalMouseButton,
        from event: NSEvent,
        anyButtonPressed: Bool
    ) {
        let point = convert(event.locationInWindow, from: nil)
        let gridPoint = gridPoint(at: point) ?? TerminalGridPoint(
            row: max(0, min(snapshot.cursorRow, snapshot.rows - 1)),
            column: max(0, min(snapshot.cursorColumn, snapshot.columns - 1))
        )
        onMouseEvent?(TerminalMouseEvent(
            action: action,
            button: button,
            row: gridPoint.row,
            column: gridPoint.column,
            modifiers: TerminalKeyModifiers(eventModifierFlags: event.modifierFlags),
            anyButtonPressed: anyButtonPressed
        ))
    }

    private func clearSelectionIfNeeded(for newSnapshot: TerminalRenderSnapshot) {
        guard let selection else {
            return
        }

        if newSnapshot.hasMouseTracking ||
            newSnapshot.columns != snapshot.columns ||
            newSnapshot.rows != snapshot.rows ||
            !selection.isValid(in: newSnapshot) ||
            selection.intersects(rows: newSnapshot.dirtyRows) {
            self.selection = nil
        }
    }

    private func gridPoint(at point: NSPoint) -> TerminalGridPoint? {
        let cellSize = measuredCellSize
        let inset = TerminalGridMetrics.contentInset
        let column = Int(floor((point.x - inset) / cellSize.width))
        let row = Int(floor((point.y - inset) / cellSize.height))
        guard row >= 0, row < snapshot.rows, column >= 0, column < snapshot.columns else {
            return nil
        }

        return TerminalGridPoint(row: row, column: column)
    }

    private func cachedColor(for color: TerminalColor) -> NSColor {
        if let cachedColor = colorCache[color] {
            return cachedColor
        }

        let resolvedColor = color.nsColor
        colorCache[color] = resolvedColor
        return resolvedColor
    }
}
enum TerminalGridMetrics {
    static let fontSize: CGFloat = 10.5
    static let contentInset: CGFloat = 3
}

private extension TerminalCell {
    var hasVisibleGlyph: Bool {
        !character.isEmpty && character != " " && character != "\t"
    }
}

private extension TerminalCellStyle {
    var hasTextDecoration: Bool {
        underlineStyle != .none || isStrikethrough || isOverline
    }
}
