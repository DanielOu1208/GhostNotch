import AppKit
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

    static let powerlineFallbackCharacters: Set<Character> = ["\u{E0B0}", "\u{E0B1}", "\u{E0B2}", "\u{E0B3}"]

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
        guard powerlineFallbackCharacters.contains(character) else {
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
