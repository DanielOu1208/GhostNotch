import AppKit
import CoreText
import SwiftUI

struct TerminalGridSurfaceView: NSViewRepresentable {
    let snapshot: TerminalRenderSnapshot
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
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TerminalGridView, context: Context) {
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        view.needsDisplay = true
        view.reportSizeIfNeeded()

        guard context.coordinator.lastFocusRequestID != focusRequestID else {
            return
        }

        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: TerminalGridView?
        var lastFocusRequestID = 0
    }
}

final class TerminalGridView: NSView {
    var snapshot = TerminalRenderSnapshot.empty()
    var onInput: ((Data) -> Void)?
    var onKeyEvent: ((TerminalKeyEvent) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onResize: ((Int, Int, Int, Int) -> Void)?

    private let typography = TerminalGridTypography(size: TerminalGridMetrics.fontSize)
    private var lastReportedResize: TerminalGridResize?
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
    }

    func reportSizeIfNeeded() {
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
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? NSScreen.main?.backingScaleFactor ?? 1
        return (
            width: max(1, Int((measuredCellSize.width * scale).rounded())),
            height: max(1, Int((measuredCellSize.height * scale).rounded()))
        )
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

        guard !cell.widthRole.isSpacer,
              !cell.character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let resolvedForeground = foreground.nsColor.withAlphaComponent(0.92)
        if TerminalBlockElementRenderer.draw(cell.character, foreground: resolvedForeground, in: textRect) {
            return
        }

        if TerminalBoxDrawingRenderer.draw(cell.character, foreground: resolvedForeground, in: textRect) {
            return
        }

        typography.draw(
            cell.character,
            style: style,
            foreground: resolvedForeground,
            in: textRect,
            viewHeight: bounds.height
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

private struct TerminalGridResize: Equatable {
    let columns: Int
    let rows: Int
    let cellWidthPixels: Int
    let cellHeightPixels: Int
}

private enum TerminalBlockElementRenderer {
    private struct Fill {
        let xRange: ClosedRange<Int>
        let yRange: ClosedRange<Int>
        let alpha: CGFloat

        init(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>, alpha: CGFloat = 1) {
            self.xRange = xRange
            self.yRange = yRange
            self.alpha = alpha
        }
    }

    static func draw(_ text: String, foreground: NSColor, in rect: NSRect) -> Bool {
        guard text.count == 1,
              let character = text.first,
              let fills = fills[character] else {
            return false
        }

        for fill in fills {
            foreground.withAlphaComponent(foreground.alphaComponent * fill.alpha).setFill()
            quadrantRect(xRange: fill.xRange, yRange: fill.yRange, in: rect).fill()
        }

        return true
    }

    private static func quadrantRect(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>, in rect: NSRect) -> NSRect {
        let xUnit = rect.width / 2
        let yUnit = rect.height / 2
        let minX = rect.minX + CGFloat(xRange.lowerBound) * xUnit
        let maxX = rect.minX + CGFloat(xRange.upperBound + 1) * xUnit
        let minY = rect.minY + CGFloat(yRange.lowerBound) * yUnit
        let maxY = rect.minY + CGFloat(yRange.upperBound + 1) * yUnit

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static let full = Fill(xRange: 0...1, yRange: 0...1)
    private static let top = Fill(xRange: 0...1, yRange: 0...0)
    private static let bottom = Fill(xRange: 0...1, yRange: 1...1)
    private static let left = Fill(xRange: 0...0, yRange: 0...1)
    private static let right = Fill(xRange: 1...1, yRange: 0...1)
    private static let topLeft = Fill(xRange: 0...0, yRange: 0...0)
    private static let topRight = Fill(xRange: 1...1, yRange: 0...0)
    private static let bottomLeft = Fill(xRange: 0...0, yRange: 1...1)
    private static let bottomRight = Fill(xRange: 1...1, yRange: 1...1)

    private static let fills: [Character: [Fill]] = [
        "█": [full],
        "■": [full],
        "▓": [Fill(xRange: 0...1, yRange: 0...1, alpha: 0.78)],
        "▒": [Fill(xRange: 0...1, yRange: 0...1, alpha: 0.5)],
        "░": [Fill(xRange: 0...1, yRange: 0...1, alpha: 0.28)],
        "▀": [top],
        "▄": [bottom],
        "▌": [left],
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

private enum TerminalBoxDrawingRenderer {
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

    static func draw(_ text: String, foreground: NSColor, in rect: NSRect) -> Bool {
        guard text.count == 1,
              let character = text.first,
              let glyph = glyphs[character] else {
            return false
        }

        foreground.setFill()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        if let left = glyph.left {
            drawHorizontal(left, from: rect.minX, to: center.x, y: center.y)
        }
        if let right = glyph.right {
            drawHorizontal(right, from: center.x, to: rect.maxX, y: center.y)
        }
        if let up = glyph.up {
            drawVertical(up, x: center.x, from: rect.minY, to: center.y)
        }
        if let down = glyph.down {
            drawVertical(down, x: center.x, from: center.y, to: rect.maxY)
        }

        return true
    }

    private static func drawHorizontal(_ stroke: Stroke, from startX: CGFloat, to endX: CGFloat, y: CGFloat) {
        guard endX > startX else {
            return
        }

        switch stroke {
        case .light:
            NSRect(x: startX, y: y - 0.5, width: endX - startX, height: 1).fill()
        case .heavy:
            NSRect(x: startX, y: y - 0.8, width: endX - startX, height: 1.6).fill()
        case .double:
            NSRect(x: startX, y: y - 1.8, width: endX - startX, height: 1).fill()
            NSRect(x: startX, y: y + 0.8, width: endX - startX, height: 1).fill()
        }
    }

    private static func drawVertical(_ stroke: Stroke, x: CGFloat, from startY: CGFloat, to endY: CGFloat) {
        guard endY > startY else {
            return
        }

        switch stroke {
        case .light:
            NSRect(x: x - 0.5, y: startY, width: 1, height: endY - startY).fill()
        case .heavy:
            NSRect(x: x - 0.8, y: startY, width: 1.6, height: endY - startY).fill()
        case .double:
            NSRect(x: x - 1.8, y: startY, width: 1, height: endY - startY).fill()
            NSRect(x: x + 0.8, y: startY, width: 1, height: endY - startY).fill()
        }
    }

    private static let glyphs: [Character: Glyph] = [
        "─": Glyph(right: .light, left: .light),
        "━": Glyph(right: .heavy, left: .heavy),
        "│": Glyph(up: .light, down: .light),
        "┃": Glyph(up: .heavy, down: .heavy),
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
        "┠": Glyph(up: .heavy, right: .light, down: .heavy),
        "┣": Glyph(up: .heavy, right: .heavy, down: .heavy),
        "┤": Glyph(up: .light, down: .light, left: .light),
        "┥": Glyph(up: .light, down: .light, left: .heavy),
        "┨": Glyph(up: .heavy, down: .heavy, left: .light),
        "┫": Glyph(up: .heavy, down: .heavy, left: .heavy),
        "┬": Glyph(right: .light, down: .light, left: .light),
        "┯": Glyph(right: .light, down: .heavy, left: .light),
        "┳": Glyph(right: .heavy, down: .heavy, left: .heavy),
        "┴": Glyph(up: .light, right: .light, left: .light),
        "┷": Glyph(up: .heavy, right: .light, left: .light),
        "┻": Glyph(up: .heavy, right: .heavy, left: .heavy),
        "┼": Glyph(up: .light, right: .light, down: .light, left: .light),
        "╂": Glyph(up: .heavy, right: .light, down: .heavy, left: .light),
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

        let codeUnits = Array(text.utf16).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: codeUnits.count)
        let supportsText = codeUnits.withUnsafeBufferPointer { codeUnitBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(baseCTFont, codeUnitBuffer.baseAddress!, glyphBuffer.baseAddress!, codeUnitBuffer.count)
            }
        }

        guard !supportsText else {
            return baseCTFont
        }

        return CTFontCreateForString(baseCTFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
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
