import AppKit
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
