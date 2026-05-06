import AppKit
import SwiftUI

struct TerminalGridSurfaceView: NSViewRepresentable {
    let snapshot: TerminalRenderSnapshot
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (Int) -> Void
    let onResize: (Int, Int) -> Void

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
    var onResize: ((Int, Int) -> Void)?

    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private var lastReportedSize: NSSize = .zero
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
              let input = TerminalInputMapping.data(forPastedText: pastedText) else {
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

        guard abs(visibleSize.width - lastReportedSize.width) >= 8 ||
              abs(visibleSize.height - lastReportedSize.height) >= 8 else {
            return
        }

        lastReportedSize = visibleSize
        let cellSize = measuredCellSize
        let cols = Int(max(2, floor((visibleSize.width - 8) / cellSize.width)))
        let rows = Int(max(1, floor((visibleSize.height - 8) / cellSize.height)))
        onResize?(cols, rows)
    }

    private var measuredCellSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = ceil(("W" as NSString).size(withAttributes: attributes).width) + 1
        let height = ceil(font.ascender - font.descender + font.leading) + 2
        return NSSize(width: max(width, 7), height: max(height, 15))
    }

    private func drawCell(_ cell: TerminalCell, row: Int, column: Int, cellSize: NSSize) {
        let rect = NSRect(
            x: CGFloat(column) * cellSize.width + 4,
            y: CGFloat(row) * cellSize.height + 4,
            width: cellSize.width,
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

        guard !cell.character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let drawFont = style.isBold ? boldFont : font
        var attributes: [NSAttributedString.Key: Any] = [
            .font: drawFont,
            .foregroundColor: foreground.nsColor.withAlphaComponent(0.92),
        ]
        if style.isItalic {
            attributes[.obliqueness] = 0.18
        }

        (cell.character as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: attributes)
    }

    private func drawCursor(cellSize: NSSize) {
        guard snapshot.cursorVisible else {
            return
        }

        let rect: NSRect
        switch snapshot.cursorStyle {
        case .bar:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + 4,
                y: CGFloat(snapshot.cursorRow) * cellSize.height + 4,
                width: 1.5,
                height: cellSize.height
            )
        case .block, .hollowBlock:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + 4,
                y: CGFloat(snapshot.cursorRow) * cellSize.height + 4,
                width: cellSize.width,
                height: cellSize.height
            )
        case .underline:
            rect = NSRect(
                x: CGFloat(snapshot.cursorColumn) * cellSize.width + 4,
                y: CGFloat(snapshot.cursorRow + 1) * cellSize.height + 2,
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
        let column = Int(floor((point.x - 4) / cellSize.width))
        let row = Int(floor((point.y - 4) / cellSize.height))
        guard row >= 0, row < snapshot.rows, column >= 0, column < snapshot.columns else {
            return nil
        }

        return TerminalGridPoint(row: row, column: column)
    }
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
