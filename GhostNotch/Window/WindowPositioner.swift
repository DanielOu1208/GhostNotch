import AppKit
import CoreGraphics

struct IslandMetrics {
    static let physicalNotchReferenceWidth: CGFloat = 220
    static let collapsedFallbackSize = NSSize(width: 280, height: 38)
    static let hoverFallbackSize = NSSize(width: 420, height: 112)
    static let expandedSize = NSSize(width: 822.8, height: 562)
    static let minimumHoverHeight: CGFloat = 112
    static let hoverNotchClearance: CGFloat = 8
    static let notchControlWidth: CGFloat = 40
    static let notchControlHeight: CGFloat = 32
    static let notchCapsuleGroupInset: CGFloat = 2
    static let hoverControlLabelHeight: CGFloat = 14
    static let hoverControlLabelSpacing: CGFloat = 4
    static let hoverControlBottomPadding: CGFloat = 12

    static var currentNotchReferenceWidth: CGFloat {
        notchReferenceWidth(on: WindowPositioner.notchScreen)
    }

    static var collapsedSize: NSSize {
        collapsedSize(on: WindowPositioner.notchScreen)
    }

    static var hoverSize: NSSize {
        hoverSize(on: WindowPositioner.notchScreen)
    }

    static func collapsedSize(on screen: NSScreen) -> NSSize {
        NSSize(width: notchReferenceWidth(on: screen) + 60, height: max(notchHeight(on: screen), collapsedFallbackSize.height))
    }

    static func hoverSize(on screen: NSScreen) -> NSSize {
        NSSize(
            width: max(notchReferenceWidth(on: screen) + 200, hoverFallbackSize.width),
            height: hoverHeight(forNotchHeight: notchHeight(on: screen))
        )
    }

    static func hoverHeight(forNotchHeight notchHeight: CGFloat) -> CGFloat {
        max(
            minimumHoverHeight,
            notchHeight
                + hoverNotchClearance
                + hoverControlLabelHeight
                + hoverControlLabelSpacing
                + notchControlHeight
                + notchCapsuleGroupInset * 2
                + hoverControlBottomPadding
        )
    }

    static func notchReferenceWidth(on screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let measuredWidth = screen.frame.width - leftWidth - rightWidth
            if measuredWidth > 0, measuredWidth < screen.frame.width {
                return measuredWidth
            }
        }

        return physicalNotchReferenceWidth
    }

    static func notchHeight(on screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let measuredHeight = screen.safeAreaInsets.top
            if measuredHeight > 0 {
                return measuredHeight
            }
        }

        return collapsedFallbackSize.height
    }
}

enum IslandState: Equatable {
    case collapsed
    case hover
    case expanded

    func size(on screen: NSScreen) -> NSSize {
        switch self {
        case .collapsed:
            IslandMetrics.collapsedSize(on: screen)
        case .hover:
            IslandMetrics.hoverSize(on: screen)
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
        let size = state.size(on: screen)
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
