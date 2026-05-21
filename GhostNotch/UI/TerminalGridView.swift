import AppKit

final class TerminalGridView: NSView {
    var snapshot = TerminalRenderSnapshot.empty()
    var onInput: ((Data) -> Void)?
    var onKeyEvent: ((TerminalKeyEvent) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onResize: ((Int, Int, Int, Int) -> Void)?
    var onMovedToWindow: (() -> Void)?
    var allowsResizeReporting = true

    private let typography = TerminalGridTypography(size: TerminalGridMetrics.fontSize)
    var lastReportedResize: TerminalGridResize?
    private var selection: TerminalSelection?

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
        bounds.fill()

        let cellSize = measuredCellSize
        for row in 0..<snapshot.rows {
            for column in 0..<snapshot.columns {
                drawCell(snapshot.cell(row: row, column: column), row: row, column: column, cellSize: cellSize)
            }
        }

        drawCursor(cellSize: cellSize)
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
        guard !snapshot.isAlternateScreen else {
            super.scrollWheel(with: event)
            return
        }

        let cellSize = measuredCellSize
        let preciseRows = -event.scrollingDeltaY / max(cellSize.height, 1)
        let rowDelta = Int(preciseRows.rounded())
        guard rowDelta != 0 else {
            return
        }

        onScroll?(rowDelta)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard !snapshot.hasMouseTracking else {
            super.mouseDown(with: event)
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
            super.mouseDragged(with: event)
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
        let cols = Int(max(2, floor((visibleSize.width - inset * 2) / cellSize.width)))
        let rows = Int(max(1, floor((visibleSize.height - inset * 2) / cellSize.height)))
        let cellPixelSize = measuredCellPixelSize
        let resize = TerminalGridResize(
            columns: cols,
            rows: rows,
            cellWidthPixels: cellPixelSize.width,
            cellHeightPixels: cellPixelSize.height
        )

        guard resize != lastReportedResize else {
            return
        }

        lastReportedResize = resize
        onResize?(cols, rows, cellPixelSize.width, cellPixelSize.height)
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

        if selection?.contains(row: row, column: column) == true {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
            rect.fill()
        } else if background != .background {
            background.nsColor.setFill()
            rect.fill()
        }

        guard !cell.widthRole.isSpacer, !style.isInvisible else {
            return
        }

        let resolvedForeground = foreground.nsColor.withAlphaComponent(style.isFaint ? 0.5 : 0.92)
        let hasVisibleGlyph = !cell.character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        TerminalTextDecorationRenderer.draw(
            style: style,
            foreground: resolvedForeground,
            in: textRect,
            scale: backingScale
        )
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

        TerminalColor.cursor.nsColor.withAlphaComponent(0.9).setFill()
        if snapshot.cursorStyle == .hollowBlock {
            rect.frame(withWidth: 1.2)
        } else {
            rect.fill()
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
}
enum TerminalGridMetrics {
    static let fontSize: CGFloat = 10.5
    static let contentInset: CGFloat = 3
}
