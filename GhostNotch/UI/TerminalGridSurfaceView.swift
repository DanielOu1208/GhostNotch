import AppKit
import CoreText
import SwiftUI

struct TerminalGridSurfaceView: NSViewRepresentable {
    let snapshot: TerminalRenderSnapshot
    let initialLastReportedResize: TerminalGridResize?
    let allowsResizeReporting: Bool
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (Int) -> Void
    let onResize: (Int, Int, Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalGridView {
        let view = TerminalGridView()
        view.lastReportedResize = initialLastReportedResize
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        view.allowsResizeReporting = allowsResizeReporting
        view.onMovedToWindow = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator, coordinator.shouldRetryFocusOnWindowAttach else {
                return
            }
            Self.applyFocus(to: view, coordinator: coordinator)
        }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TerminalGridView, context: Context) {
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        view.allowsResizeReporting = allowsResizeReporting
        view.needsDisplay = true
        if allowsResizeReporting {
            view.reportSizeIfNeeded()
        }

        guard context.coordinator.lastFocusRequestID != focusRequestID else {
            return
        }

        context.coordinator.lastFocusRequestID = focusRequestID
        Self.applyFocus(to: view, coordinator: context.coordinator)
    }

    private static func applyFocus(to view: TerminalGridView, coordinator: Coordinator) {
        let attempt: () -> Bool = {
            guard let window = view.window else {
                return false
            }
            return window.makeFirstResponder(view)
        }

        if attempt() {
            coordinator.shouldRetryFocusOnWindowAttach = false
            return
        }

        coordinator.shouldRetryFocusOnWindowAttach = true
        DispatchQueue.main.async {
            if attempt() {
                coordinator.shouldRetryFocusOnWindowAttach = false
            }
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: TerminalGridView?
        var lastFocusRequestID = 0
        var shouldRetryFocusOnWindowAttach = false
    }
}

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

private enum TerminalGridMetrics {
    static let fontSize: CGFloat = 10.5
    static let contentInset: CGFloat = 3
}

struct TerminalGlyphFill: Equatable {
    let rect: NSRect
    let alpha: CGFloat
}

enum TerminalCellGlyphRenderer {
    private struct FractionalFill {
        let xStart: CGFloat
        let xEnd: CGFloat
        let yStart: CGFloat
        let yEnd: CGFloat
        let alpha: CGFloat

        init(xStart: CGFloat, xEnd: CGFloat, yStart: CGFloat, yEnd: CGFloat, alpha: CGFloat = 1) {
            self.xStart = xStart
            self.xEnd = xEnd
            self.yStart = yStart
            self.yEnd = yEnd
            self.alpha = alpha
        }
    }

    static func draw(_ text: String, foreground: NSColor, in rect: NSRect, scale: CGFloat, fontSupportsText: Bool) -> Bool {
        guard text.count == 1,
              let character = text.first else {
            return false
        }

        if let fills = blockFillRects(for: character, in: rect, scale: scale) {
            for fill in fills {
                foreground.withAlphaComponent(foreground.alphaComponent * fill.alpha).setFill()
                fill.rect.fill()
            }
            return true
        }

        if drawBox(character, foreground: foreground, in: rect, scale: scale) {
            return true
        }

        if !fontSupportsText, drawPowerline(character, foreground: foreground, in: rect, scale: scale) {
            return true
        }

        return false
    }

    static func blockFillRects(for character: Character, in rect: NSRect, scale: CGFloat) -> [TerminalGlyphFill]? {
        guard let fills = blockFills[character] else {
            return nil
        }

        return fills.map { fill in
            TerminalGlyphFill(
                rect: TerminalPixelGrid.align(
                    NSRect(
                        x: rect.minX + rect.width * fill.xStart,
                        y: rect.minY + rect.height * fill.yStart,
                        width: rect.width * (fill.xEnd - fill.xStart),
                        height: rect.height * (fill.yEnd - fill.yStart)
                    ),
                    scale: scale
                ),
                alpha: fill.alpha
            )
        }
    }

    static func boxStrokeRects(for character: Character, in rect: NSRect, scale: CGFloat) -> [NSRect]? {
        guard let glyph = boxGlyphs[character] else {
            return nil
        }

        var rects: [NSRect] = []
        let center = CGPoint(
            x: TerminalPixelGrid.align(rect.midX, scale: scale),
            y: TerminalPixelGrid.align(rect.midY, scale: scale)
        )

        if let left = glyph.left {
            rects.append(contentsOf: horizontalStrokeRects(left, from: rect.minX, to: center.x, y: center.y, scale: scale))
        }
        if let right = glyph.right {
            rects.append(contentsOf: horizontalStrokeRects(right, from: center.x, to: rect.maxX, y: center.y, scale: scale))
        }
        if let up = glyph.up {
            rects.append(contentsOf: verticalStrokeRects(up, x: center.x, from: rect.minY, to: center.y, scale: scale))
        }
        if let down = glyph.down {
            rects.append(contentsOf: verticalStrokeRects(down, x: center.x, from: center.y, to: rect.maxY, scale: scale))
        }

        return rects
    }

    static func powerlineFallbackCharacters() -> Set<Character> {
        ["\u{E0B0}", "\u{E0B1}", "\u{E0B2}", "\u{E0B3}"]
    }

    private static func drawBox(_ character: Character, foreground: NSColor, in rect: NSRect, scale: CGFloat) -> Bool {
        guard let strokeRects = boxStrokeRects(for: character, in: rect, scale: scale) else {
            return false
        }

        foreground.setFill()
        for rect in strokeRects {
            rect.fill()
        }

        if diagonalBoxCharacters.contains(character) {
            drawDiagonal(character, foreground: foreground, in: rect, scale: scale)
        }

        return true
    }

    private static func drawPowerline(_ character: Character, foreground: NSColor, in rect: NSRect, scale: CGFloat) -> Bool {
        guard powerlineFallbackCharacters().contains(character) else {
            return false
        }

        foreground.setFill()
        let path = NSBezierPath()
        switch character {
        case "\u{E0B0}":
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            path.fill()
        case "\u{E0B2}":
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.line(to: CGPoint(x: rect.minX, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.close()
            path.fill()
        case "\u{E0B1}", "\u{E0B3}":
            let startX = character == "\u{E0B1}" ? rect.minX : rect.maxX
            let endX = character == "\u{E0B1}" ? rect.maxX : rect.minX
            let line = NSBezierPath()
            line.lineWidth = max(1 / max(scale, 1), 1)
            line.move(to: CGPoint(x: startX, y: rect.minY))
            line.line(to: CGPoint(x: endX, y: rect.maxY))
            foreground.setStroke()
            line.stroke()
        default:
            return false
        }
        return true
    }

    private static func drawDiagonal(_ character: Character, foreground: NSColor, in rect: NSRect, scale: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = TerminalPixelGrid.alignSize(1.2, scale: scale)
        foreground.setStroke()

        switch character {
        case "╱":
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        case "╲":
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case "╳":
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            return
        }
        path.stroke()
    }

    private static func horizontalStrokeRects(_ stroke: Stroke, from startX: CGFloat, to endX: CGFloat, y: CGFloat, scale: CGFloat) -> [NSRect] {
        guard endX > startX else {
            return []
        }

        let width = endX - startX
        switch stroke {
        case .light:
            return [TerminalPixelGrid.strokeRect(x: startX, y: y, width: width, height: 1, axis: .horizontal, scale: scale)]
        case .heavy:
            return [TerminalPixelGrid.strokeRect(x: startX, y: y, width: width, height: 1.8, axis: .horizontal, scale: scale)]
        case .double:
            let offset = TerminalPixelGrid.alignSize(1.5, scale: scale)
            return [
                TerminalPixelGrid.strokeRect(x: startX, y: y - offset, width: width, height: 1, axis: .horizontal, scale: scale),
                TerminalPixelGrid.strokeRect(x: startX, y: y + offset, width: width, height: 1, axis: .horizontal, scale: scale),
            ]
        }
    }

    private static func verticalStrokeRects(_ stroke: Stroke, x: CGFloat, from startY: CGFloat, to endY: CGFloat, scale: CGFloat) -> [NSRect] {
        guard endY > startY else {
            return []
        }

        let height = endY - startY
        switch stroke {
        case .light:
            return [TerminalPixelGrid.strokeRect(x: x, y: startY, width: 1, height: height, axis: .vertical, scale: scale)]
        case .heavy:
            return [TerminalPixelGrid.strokeRect(x: x, y: startY, width: 1.8, height: height, axis: .vertical, scale: scale)]
        case .double:
            let offset = TerminalPixelGrid.alignSize(1.5, scale: scale)
            return [
                TerminalPixelGrid.strokeRect(x: x - offset, y: startY, width: 1, height: height, axis: .vertical, scale: scale),
                TerminalPixelGrid.strokeRect(x: x + offset, y: startY, width: 1, height: height, axis: .vertical, scale: scale),
            ]
        }
    }

    private enum Stroke {
        case light
        case heavy
        case double
    }

    private struct Glyph {
        let up: Stroke?
        let right: Stroke?
        let down: Stroke?
        let left: Stroke?

        init(up: Stroke? = nil, right: Stroke? = nil, down: Stroke? = nil, left: Stroke? = nil) {
            self.up = up
            self.right = right
            self.down = down
            self.left = left
        }
    }

    private static let full = FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 1)
    private static let top = FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 0.5)
    private static let bottom = FractionalFill(xStart: 0, xEnd: 1, yStart: 0.5, yEnd: 1)
    private static let left = FractionalFill(xStart: 0, xEnd: 0.5, yStart: 0, yEnd: 1)
    private static let right = FractionalFill(xStart: 0.5, xEnd: 1, yStart: 0, yEnd: 1)
    private static let topLeft = FractionalFill(xStart: 0, xEnd: 0.5, yStart: 0, yEnd: 0.5)
    private static let topRight = FractionalFill(xStart: 0.5, xEnd: 1, yStart: 0, yEnd: 0.5)
    private static let bottomLeft = FractionalFill(xStart: 0, xEnd: 0.5, yStart: 0.5, yEnd: 1)
    private static let bottomRight = FractionalFill(xStart: 0.5, xEnd: 1, yStart: 0.5, yEnd: 1)

    private static let blockFills: [Character: [FractionalFill]] = [
        "█": [full],
        "■": [full],
        "▓": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 1, alpha: 0.78)],
        "▒": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 1, alpha: 0.5)],
        "░": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 1, alpha: 0.28)],
        "▔": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0, yEnd: 0.125)],
        "▀": [top],
        "▄": [bottom],
        "▁": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.875, yEnd: 1)],
        "▂": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.75, yEnd: 1)],
        "▃": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.625, yEnd: 1)],
        "▅": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.375, yEnd: 1)],
        "▆": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.25, yEnd: 1)],
        "▇": [FractionalFill(xStart: 0, xEnd: 1, yStart: 0.125, yEnd: 1)],
        "▏": [FractionalFill(xStart: 0, xEnd: 0.125, yStart: 0, yEnd: 1)],
        "▎": [FractionalFill(xStart: 0, xEnd: 0.25, yStart: 0, yEnd: 1)],
        "▍": [FractionalFill(xStart: 0, xEnd: 0.375, yStart: 0, yEnd: 1)],
        "▌": [left],
        "▋": [FractionalFill(xStart: 0, xEnd: 0.625, yStart: 0, yEnd: 1)],
        "▊": [FractionalFill(xStart: 0, xEnd: 0.75, yStart: 0, yEnd: 1)],
        "▉": [FractionalFill(xStart: 0, xEnd: 0.875, yStart: 0, yEnd: 1)],
        "▐": [right],
        "▖": [bottomLeft],
        "▗": [bottomRight],
        "▘": [topLeft],
        "▝": [topRight],
        "▙": [topLeft, bottomLeft, bottomRight],
        "▚": [topLeft, bottomRight],
        "▛": [topLeft, topRight, bottomLeft],
        "▜": [topLeft, topRight, bottomRight],
        "▞": [topRight, bottomLeft],
        "▟": [topRight, bottomLeft, bottomRight],
    ]
}

private extension TerminalCellGlyphRenderer {
    private static let diagonalBoxCharacters: Set<Character> = ["╱", "╲", "╳"]

    private static let boxGlyphs: [Character: Glyph] = [
        "─": Glyph(right: .light, left: .light),
        "━": Glyph(right: .heavy, left: .heavy),
        "┄": Glyph(right: .light, left: .light),
        "┅": Glyph(right: .heavy, left: .heavy),
        "┈": Glyph(right: .light, left: .light),
        "┉": Glyph(right: .heavy, left: .heavy),
        "│": Glyph(up: .light, down: .light),
        "┃": Glyph(up: .heavy, down: .heavy),
        "┆": Glyph(up: .light, down: .light),
        "┇": Glyph(up: .heavy, down: .heavy),
        "┊": Glyph(up: .light, down: .light),
        "┋": Glyph(up: .heavy, down: .heavy),
        "┌": Glyph(right: .light, down: .light),
        "┍": Glyph(right: .heavy, down: .light),
        "┎": Glyph(right: .light, down: .heavy),
        "┏": Glyph(right: .heavy, down: .heavy),
        "┐": Glyph(down: .light, left: .light),
        "┑": Glyph(down: .light, left: .heavy),
        "┒": Glyph(down: .heavy, left: .light),
        "┓": Glyph(down: .heavy, left: .heavy),
        "└": Glyph(up: .light, right: .light),
        "┕": Glyph(up: .light, right: .heavy),
        "┖": Glyph(up: .heavy, right: .light),
        "┗": Glyph(up: .heavy, right: .heavy),
        "┘": Glyph(up: .light, left: .light),
        "┙": Glyph(up: .light, left: .heavy),
        "┚": Glyph(up: .heavy, left: .light),
        "┛": Glyph(up: .heavy, left: .heavy),
        "├": Glyph(up: .light, right: .light, down: .light),
        "┝": Glyph(up: .light, right: .heavy, down: .light),
        "┞": Glyph(up: .heavy, right: .light, down: .light),
        "┟": Glyph(up: .light, right: .light, down: .heavy),
        "┠": Glyph(up: .heavy, right: .light, down: .heavy),
        "┡": Glyph(up: .heavy, right: .heavy, down: .light),
        "┢": Glyph(up: .light, right: .heavy, down: .heavy),
        "┣": Glyph(up: .heavy, right: .heavy, down: .heavy),
        "┤": Glyph(up: .light, down: .light, left: .light),
        "┥": Glyph(up: .light, down: .light, left: .heavy),
        "┦": Glyph(up: .heavy, down: .light, left: .light),
        "┧": Glyph(up: .light, down: .heavy, left: .light),
        "┨": Glyph(up: .heavy, down: .heavy, left: .light),
        "┩": Glyph(up: .heavy, down: .light, left: .heavy),
        "┪": Glyph(up: .light, down: .heavy, left: .heavy),
        "┫": Glyph(up: .heavy, down: .heavy, left: .heavy),
        "┬": Glyph(right: .light, down: .light, left: .light),
        "┭": Glyph(right: .heavy, down: .light, left: .light),
        "┮": Glyph(right: .light, down: .light, left: .heavy),
        "┯": Glyph(right: .light, down: .heavy, left: .light),
        "┰": Glyph(right: .heavy, down: .heavy, left: .light),
        "┱": Glyph(right: .light, down: .heavy, left: .heavy),
        "┲": Glyph(right: .heavy, down: .light, left: .heavy),
        "┳": Glyph(right: .heavy, down: .heavy, left: .heavy),
        "┴": Glyph(up: .light, right: .light, left: .light),
        "┵": Glyph(up: .light, right: .heavy, left: .light),
        "┶": Glyph(up: .light, right: .light, left: .heavy),
        "┷": Glyph(up: .heavy, right: .light, left: .light),
        "┸": Glyph(up: .heavy, right: .heavy, left: .light),
        "┹": Glyph(up: .heavy, right: .light, left: .heavy),
        "┺": Glyph(up: .light, right: .heavy, left: .heavy),
        "┻": Glyph(up: .heavy, right: .heavy, left: .heavy),
        "┼": Glyph(up: .light, right: .light, down: .light, left: .light),
        "┽": Glyph(up: .light, right: .heavy, down: .light, left: .light),
        "┾": Glyph(up: .heavy, right: .light, down: .light, left: .light),
        "┿": Glyph(up: .light, right: .light, down: .heavy, left: .light),
        "╀": Glyph(up: .light, right: .light, down: .light, left: .heavy),
        "╁": Glyph(up: .heavy, right: .heavy, down: .light, left: .light),
        "╂": Glyph(up: .heavy, right: .light, down: .heavy, left: .light),
        "╃": Glyph(up: .light, right: .heavy, down: .heavy, left: .light),
        "╄": Glyph(up: .light, right: .light, down: .heavy, left: .heavy),
        "╅": Glyph(up: .heavy, right: .light, down: .light, left: .heavy),
        "╆": Glyph(up: .light, right: .heavy, down: .light, left: .heavy),
        "╇": Glyph(up: .heavy, right: .light, down: .heavy, left: .heavy),
        "╈": Glyph(up: .light, right: .heavy, down: .heavy, left: .heavy),
        "╉": Glyph(up: .heavy, right: .heavy, down: .light, left: .heavy),
        "╊": Glyph(up: .heavy, right: .heavy, down: .heavy, left: .light),
        "╋": Glyph(up: .heavy, right: .heavy, down: .heavy, left: .heavy),
        "╭": Glyph(right: .light, down: .light),
        "╮": Glyph(down: .light, left: .light),
        "╰": Glyph(up: .light, right: .light),
        "╯": Glyph(up: .light, left: .light),
        "═": Glyph(right: .double, left: .double),
        "║": Glyph(up: .double, down: .double),
        "╔": Glyph(right: .double, down: .double),
        "╗": Glyph(down: .double, left: .double),
        "╚": Glyph(up: .double, right: .double),
        "╝": Glyph(up: .double, left: .double),
        "╠": Glyph(up: .double, right: .double, down: .double),
        "╣": Glyph(up: .double, down: .double, left: .double),
        "╦": Glyph(right: .double, down: .double, left: .double),
        "╩": Glyph(up: .double, right: .double, left: .double),
        "╬": Glyph(up: .double, right: .double, down: .double, left: .double),
        "╒": Glyph(right: .double, down: .light),
        "╓": Glyph(right: .light, down: .double),
        "╕": Glyph(down: .light, left: .double),
        "╖": Glyph(down: .double, left: .light),
        "╘": Glyph(up: .light, right: .double),
        "╙": Glyph(up: .double, right: .light),
        "╛": Glyph(up: .light, left: .double),
        "╜": Glyph(up: .double, left: .light),
        "╞": Glyph(up: .light, right: .double, down: .light),
        "╟": Glyph(up: .double, right: .light, down: .double),
        "╡": Glyph(up: .light, down: .light, left: .double),
        "╢": Glyph(up: .double, down: .double, left: .light),
        "╤": Glyph(right: .double, down: .light, left: .double),
        "╥": Glyph(right: .light, down: .double, left: .light),
        "╧": Glyph(up: .light, right: .double, left: .double),
        "╨": Glyph(up: .double, right: .light, left: .light),
        "╪": Glyph(up: .light, right: .double, down: .light, left: .double),
        "╫": Glyph(up: .double, right: .light, down: .double, left: .light),
    ]
}

enum TerminalTextDecorationRenderer {
    static func draw(style: TerminalCellStyle, foreground: NSColor, in rect: NSRect, scale: CGFloat) {
        let color = (style.underlineColor?.nsColor ?? foreground).withAlphaComponent(foreground.alphaComponent)
        color.setFill()

        for decorationRect in decorationRects(style: style, in: rect, scale: scale) {
            decorationRect.fill()
        }

        if style.underlineStyle == .curly {
            drawCurlyUnderline(color: color, in: rect, scale: scale)
        }
    }

    static func decorationRects(style: TerminalCellStyle, in rect: NSRect, scale: CGFloat) -> [NSRect] {
        var rects: [NSRect] = []

        switch style.underlineStyle {
        case .none, .curly:
            break
        case .single:
            rects.append(lineRect(y: rect.maxY - 2, in: rect, scale: scale))
        case .double:
            rects.append(lineRect(y: rect.maxY - 3, in: rect, scale: scale))
            rects.append(lineRect(y: rect.maxY - 1, in: rect, scale: scale))
        case .dotted:
            rects.append(contentsOf: segmentedLineRects(y: rect.maxY - 2, in: rect, scale: scale, segment: 1, gap: 2))
        case .dashed:
            rects.append(contentsOf: segmentedLineRects(y: rect.maxY - 2, in: rect, scale: scale, segment: 4, gap: 2))
        }

        if style.isStrikethrough {
            rects.append(lineRect(y: rect.midY, in: rect, scale: scale))
        }

        if style.isOverline {
            rects.append(lineRect(y: rect.minY + 1, in: rect, scale: scale))
        }

        return rects
    }

    private static func drawCurlyUnderline(color: NSColor, in rect: NSRect, scale: CGFloat) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = TerminalPixelGrid.alignSize(1, scale: scale)
        let amplitude = TerminalPixelGrid.alignSize(1.5, scale: scale)
        let baseline = TerminalPixelGrid.align(rect.maxY - 2, scale: scale)
        let wavelength = max(TerminalPixelGrid.alignSize(4, scale: scale), 2)

        var x = rect.minX
        path.move(to: CGPoint(x: x, y: baseline))
        while x < rect.maxX {
            let midX = min(x + wavelength / 2, rect.maxX)
            let endX = min(x + wavelength, rect.maxX)
            path.curve(
                to: CGPoint(x: endX, y: baseline),
                controlPoint1: CGPoint(x: x + wavelength / 4, y: baseline - amplitude),
                controlPoint2: CGPoint(x: midX + wavelength / 4, y: baseline + amplitude)
            )
            x += wavelength
        }
        path.stroke()
    }

    private static func lineRect(y: CGFloat, in rect: NSRect, scale: CGFloat) -> NSRect {
        TerminalPixelGrid.strokeRect(
            x: rect.minX,
            y: y,
            width: rect.width,
            height: 1,
            axis: .horizontal,
            scale: scale
        )
    }

    private static func segmentedLineRects(y: CGFloat, in rect: NSRect, scale: CGFloat, segment: CGFloat, gap: CGFloat) -> [NSRect] {
        var rects: [NSRect] = []
        var x = rect.minX
        while x < rect.maxX {
            let endX = min(x + segment, rect.maxX)
            rects.append(
                TerminalPixelGrid.strokeRect(
                    x: x,
                    y: y,
                    width: endX - x,
                    height: 1,
                    axis: .horizontal,
                    scale: scale
                )
            )
            x += segment + gap
        }
        return rects
    }
}

enum TerminalPixelGrid {
    enum Axis {
        case horizontal
        case vertical
    }

    static func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else {
            return value.rounded()
        }
        return (value * scale).rounded() / scale
    }

    static func alignSize(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        max(1 / max(scale, 1), align(value, scale: scale))
    }

    static func align(_ rect: NSRect, scale: CGFloat) -> NSRect {
        let minX = align(rect.minX, scale: scale)
        let minY = align(rect.minY, scale: scale)
        let maxX = align(rect.maxX, scale: scale)
        let maxY = align(rect.maxY, scale: scale)
        return NSRect(x: minX, y: minY, width: max(maxX - minX, 1 / max(scale, 1)), height: max(maxY - minY, 1 / max(scale, 1)))
    }

    static func strokeRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, axis: Axis, scale: CGFloat) -> NSRect {
        let alignedWidth = axis == .vertical ? alignSize(width, scale: scale) : width
        let alignedHeight = axis == .horizontal ? alignSize(height, scale: scale) : height
        switch axis {
        case .horizontal:
            return align(NSRect(x: x, y: y - alignedHeight / 2, width: width, height: alignedHeight), scale: scale)
        case .vertical:
            return align(NSRect(x: x - alignedWidth / 2, y: y, width: alignedWidth, height: height), scale: scale)
        }
    }
}

private struct TerminalGridTypography {
    let regularFont: NSFont
    let boldFont: NSFont
    let cellSize: NSSize
    let baselineOffset: CGFloat

    init(size: CGFloat) {
        regularFont = Self.makeFont(size: size, weight: .regular)
        boldFont = Self.makeFont(size: size, weight: .semibold, matching: regularFont)
        let regularCTFont = regularFont as CTFont
        let advance = CTFontGetAdvancesForGlyphs(regularCTFont, .horizontal, [Self.measurementGlyph(for: regularCTFont)], nil, 1)
        let width = ceil(advance)
        let ascent = ceil(CTFontGetAscent(regularCTFont))
        let descent = ceil(CTFontGetDescent(regularCTFont))
        let leading = ceil(CTFontGetLeading(regularCTFont))
        cellSize = NSSize(width: max(width, 7), height: max(ascent + descent + leading + 1, 14))
        baselineOffset = max(1, floor((cellSize.height - ascent - descent) / 2)) + ascent
    }

    func draw(_ text: String, style: TerminalCellStyle, foreground: NSColor, in rect: NSRect, viewHeight: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let baseFont = style.isBold ? boldFont : regularFont
        let drawFont = Self.font(for: text, baseFont: baseFont)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): drawFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground.cgColor,
            .ligature: 1,
        ]
        if style.isItalic {
            attributes[.obliqueness] = 0.18
        }

        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: viewHeight)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: rect.minX, y: viewHeight - rect.minY - baselineOffset)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    func supports(_ text: String) -> Bool {
        Self.supports(text, font: regularFont as CTFont)
    }

    private static func makeFont(size: CGFloat, weight: NSFont.Weight, matching baseFont: NSFont? = nil) -> NSFont {
        if let baseFont,
           let weightedFont = NSFont(
            descriptor: baseFont.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
            ]),
            size: size
           ) {
            return weightedFont
        }

        for name in preferredInstalledFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func font(for text: String, baseFont: NSFont) -> CTFont {
        let baseCTFont = baseFont as CTFont
        guard !text.isEmpty else {
            return baseCTFont
        }

        guard !supports(text, font: baseCTFont) else {
            return baseCTFont
        }

        for name in preferredInstalledFontNames {
            guard let fallbackFont = NSFont(name: name, size: baseFont.pointSize) else {
                continue
            }
            let fallbackCTFont = fallbackFont as CTFont
            if supports(text, font: fallbackCTFont) {
                return fallbackCTFont
            }
        }

        return CTFontCreateForString(baseCTFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
    }

    private static func supports(_ text: String, font: CTFont) -> Bool {
        guard !text.isEmpty else {
            return true
        }

        let codeUnits = Array(text.utf16).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: codeUnits.count)
        return codeUnits.withUnsafeBufferPointer { codeUnitBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(font, codeUnitBuffer.baseAddress!, glyphBuffer.baseAddress!, codeUnitBuffer.count)
            }
        }
    }

    private static func measurementGlyph(for font: CTFont) -> CGGlyph {
        var character: UniChar = 87
        var glyph = CGGlyph()
        _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        return glyph
    }

    private static let preferredInstalledFontNames = [
        "MesloLGS NF",
        "MesloLGS NF Regular",
        "JetBrainsMono Nerd Font",
        "JetBrains Mono NL",
        "Hack Nerd Font",
        "FiraCode Nerd Font",
        "Menlo",
    ]
}

private extension TerminalKeyEvent {
    init?(event: NSEvent) {
        let key = TerminalKey(keyCode: UInt16(event.keyCode), charactersIgnoringModifiers: event.charactersIgnoringModifiers)
        let text = TerminalKeyEvent.text(for: event, key: key)
        guard key != .unidentified || text?.isEmpty == false else {
            return nil
        }

        self.init(
            key: key,
            modifiers: TerminalKeyModifiers(event.modifierFlags),
            utf8: text,
            isRepeat: event.isARepeat
        )
    }

    private static func text(for event: NSEvent, key: TerminalKey) -> String? {
        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }

        switch key {
        case .enter, .tab, .backspace, .delete, .escape, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .home, .end, .pageUp, .pageDown, .function:
            return nil
        default:
            return characters
                .replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
        }
    }
}

private extension TerminalKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: TerminalKeyModifiers = []
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        if filtered.contains(.shift) {
            modifiers.insert(.shift)
        }
        if filtered.contains(.control) {
            modifiers.insert(.control)
        }
        if filtered.contains(.option) {
            modifiers.insert(.option)
        }
        if filtered.contains(.command) {
            modifiers.insert(.command)
        }
        self = modifiers
    }
}

private extension TerminalKey {
    init(keyCode: UInt16, charactersIgnoringModifiers: String?) {
        switch keyCode {
        case 36, 76:
            self = .enter
        case 48:
            self = .tab
        case 51:
            self = .backspace
        case 117:
            self = .delete
        case 53:
            self = .escape
        case 123:
            self = .arrowLeft
        case 124:
            self = .arrowRight
        case 125:
            self = .arrowDown
        case 126:
            self = .arrowUp
        case 115:
            self = .home
        case 119:
            self = .end
        case 116:
            self = .pageUp
        case 121:
            self = .pageDown
        case 49:
            self = .space
        case 122:
            self = .function(1)
        case 120:
            self = .function(2)
        case 99:
            self = .function(3)
        case 118:
            self = .function(4)
        case 96:
            self = .function(5)
        case 97:
            self = .function(6)
        case 98:
            self = .function(7)
        case 100:
            self = .function(8)
        case 101:
            self = .function(9)
        case 109:
            self = .function(10)
        case 103:
            self = .function(11)
        case 111:
            self = .function(12)
        default:
            if let letter = charactersIgnoringModifiers?.first, letter.isLetter {
                self = .letter(letter)
            } else {
                self = .unidentified
            }
        }
    }
}

private extension TerminalColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}
