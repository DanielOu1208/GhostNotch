import AppKit
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
