import AppKit

struct IslandMetrics {
    static let collapsedSize = NSSize(width: 96, height: 28)
    static let hoverSize = NSSize(width: 128, height: 32)
    static let expandedSize = NSSize(width: 640, height: 280)
    static let topOffset: CGFloat = 8
}

enum IslandState: Equatable {
    case collapsed
    case hover
    case expanded

    var size: NSSize {
        switch self {
        case .collapsed:
            IslandMetrics.collapsedSize
        case .hover:
            IslandMetrics.hoverSize
        case .expanded:
            IslandMetrics.expandedSize
        }
    }
}

enum WindowPositioner {
    static func frame(for state: IslandState, on screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> NSRect {
        let size = state.size
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - menuBarHeight - IslandMetrics.topOffset - size.height

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
