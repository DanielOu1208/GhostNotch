import AppKit
import SwiftUI

struct TerminalGridSurfaceView: NSViewRepresentable {
    let snapshot: TerminalRenderSnapshot
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalGridView {
        let view = TerminalGridView()
        view.snapshot = snapshot
        view.onInput = onInput
        view.onResize = onResize
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TerminalGridView, context: Context) {
        view.snapshot = snapshot
        view.onInput = onInput
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
    var onResize: ((Int, Int) -> Void)?

    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private var lastReportedSize: NSSize = .zero

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

            super.keyDown(with: event)
            return
        }

        guard let input = TerminalInputMapping.data(forKeyCode: UInt16(event.keyCode), characters: event.characters) else {
            return
        }

        onInput?(input)
    }

    @objc func paste(_ sender: Any?) {
        guard let pastedText = NSPasteboard.general.string(forType: .string),
              let input = TerminalInputMapping.data(forPastedText: pastedText) else {
            return
        }

        onInput?(input)
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

        if background != .background {
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

        let rect = NSRect(
            x: CGFloat(snapshot.cursorColumn) * cellSize.width + 4,
            y: CGFloat(snapshot.cursorRow) * cellSize.height + 4,
            width: 1.5,
            height: cellSize.height
        )
        TerminalColor.cursor.nsColor.withAlphaComponent(0.9).setFill()
        rect.fill()
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
