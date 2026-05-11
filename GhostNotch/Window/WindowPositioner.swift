import AppKit
import CoreGraphics

struct IslandMetrics {
    static let physicalNotchReferenceWidth: CGFloat = 220
    static let collapsedSize = NSSize(width: 280, height: 38)
    static let hoverSize = NSSize(width: 420, height: 72)
    static let expandedSize = NSSize(width: 748, height: 400)
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
    static var notchScreen: NSScreen {
        NSScreen.screens.first(where: \.isBuiltInDisplay) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func frame(for state: IslandState, on screen: NSScreen = WindowPositioner.notchScreen) -> NSRect {
        let size = state.size
        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

private extension NSScreen {
    var isBuiltInDisplay: Bool {
        guard
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return false
        }

        return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
    }
}
