import AppKit
import CoreGraphics
import SwiftUI

struct IslandMetrics {
    static let physicalNotchReferenceWidth: CGFloat = 220
    static let collapsedFallbackSize = NSSize(width: 280, height: 38)
    static let hoverFallbackSize = NSSize(width: 420, height: 136)
    static let expandedSize = NSSize(width: 822.8, height: 562)
    static let minimumHoverHeight: CGFloat = 136
    static let compactMarkSize: CGFloat = 22
    static let notchControlWidth: CGFloat = 40
    static let notchControlHeight: CGFloat = 32
    static let notchCapsuleGroupInset: CGFloat = 2
    static let notchCapsuleContentWidth: CGFloat = 120
    static let notchCapsuleGroupWidth = notchCapsuleContentWidth + notchCapsuleGroupInset * 2
    static let notchSelectionBackingExtraWidth: CGFloat = 5
    static let notchSelectionBackingExtraHeight: CGFloat = 4
    static let hoverControlGroupSpacing: CGFloat = 12
    static let hoverPrimaryActionWidth = notchCapsuleGroupWidth * 3 + hoverControlGroupSpacing * 2
    static let hoverPrimaryActionHeight: CGFloat = 36
    static let hoverPrimaryActionSpacing: CGFloat = 4
    static let hoverPrimaryActionBottomPadding: CGFloat = 4
    static let hoverControlLabelHeight: CGFloat = 14
    static let hoverControlLabelSpacing: CGFloat = 4
    static let hoverControlOuterPadding: CGFloat = 12

    static var currentNotchReferenceWidth: CGFloat {
        notchReferenceWidth(on: WindowPositioner.notchScreen)
    }

    static var collapsedSize: NSSize {
        collapsedSize(on: WindowPositioner.notchScreen)
    }

    static var hoverSize: NSSize {
        hoverSize(on: WindowPositioner.notchScreen)
    }

    static func notchSegmentWidth(itemCount: Int) -> CGFloat {
        notchCapsuleContentWidth / CGFloat(max(itemCount, 1))
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
                + hoverControlLabelHeight
                + hoverControlLabelSpacing
                + notchControlHeight
                + notchCapsuleGroupInset * 2
                + hoverPrimaryActionSpacing
                + hoverPrimaryActionHeight
                + hoverPrimaryActionBottomPadding
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

enum RoseThreeGeometry {
    static let particleCount = 18
    static let maximumParticleDiameter: CGFloat = 1.5
    static let activeGuideOpacity = 0.24
    static let trailSpan = 0.34
    static let loopDuration: TimeInterval = 1.8
    static let sampleCount = 96

    static func point(at phase: Double, in size: CGSize) -> CGPoint {
        let normalizedPhase = wrappedPhase(phase)
        let theta = Double.pi * normalizedPhase
        let maximumRadius = max(
            min(size.width, size.height) / 2 - maximumParticleDiameter / 2,
            0
        )
        let radius = maximumRadius * CGFloat(cos(3 * theta))

        return CGPoint(
            x: size.width / 2 + radius * CGFloat(cos(theta)),
            y: size.height / 2 + radius * CGFloat(sin(theta))
        )
    }

    static func path(in size: CGSize) -> Path {
        var path = Path()
        for index in 0...sampleCount {
            let point = point(at: Double(index) / Double(sampleCount), in: size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    static func particlePhase(headPhase: Double, index: Int) -> Double {
        let offset = trailSpan * Double(index) / Double(max(particleCount - 1, 1))
        return wrappedPhase(headPhase - offset)
    }

    static func particleScale(index: Int) -> Double {
        max(1 - Double(index) / Double(particleCount), 0)
    }

    static func wrappedPhase(_ phase: Double) -> Double {
        let remainder = phase.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
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

enum IslandTransitionCurve: Equatable {
    case spring
    case easeOut
}

struct IslandTransitionPlan: Equatable {
    static let hoverExitGrace: TimeInterval = 0.04
    static let hoverOpenDuration: TimeInterval = 0.34
    static let hoverCloseDuration: TimeInterval = 0.18
    static let reduceMotionDuration: TimeInterval = 0.08
    static let outgoingContentDurationFraction = 0.35
    static let primaryContentEntryDelayFraction = 0.25
    static let hoverSpring = Spring(settlingDuration: hoverOpenDuration, dampingRatio: 0.78)
    static let expandedSpring = Spring(settlingDuration: 0.34, dampingRatio: 0.78)

    let from: IslandState
    let to: IslandState
    let duration: TimeInterval
    let curve: IslandTransitionCurve
    let reducesMotion: Bool

    var requiresLayoutStaging: Bool {
        from == .expanded || to == .expanded
    }

    init(from: IslandState, to: IslandState, reducesMotion: Bool) {
        self.from = from
        self.to = to
        self.reducesMotion = reducesMotion

        if reducesMotion {
            duration = Self.reduceMotionDuration
        } else {
            duration = switch (from, to) {
            case (.collapsed, .hover): Self.hoverOpenDuration
            case (.hover, .collapsed): Self.hoverCloseDuration
            case (.collapsed, .expanded), (.hover, .expanded): 0.34
            case (.expanded, .collapsed), (.expanded, .hover): 0.22
            default: 0
            }
        }

        if reducesMotion {
            curve = .easeOut
        } else {
            curve = switch (from, to) {
            case (.collapsed, .hover), (.collapsed, .expanded), (.hover, .expanded):
                .spring
            default:
                .easeOut
            }
        }
    }

    func progress(at elapsedTime: TimeInterval) -> CGFloat {
        guard duration > 0 else {
            return 1
        }
        if elapsedTime >= duration {
            return 1
        }

        let elapsedTime = max(elapsedTime, 0)
        switch curve {
        case .spring:
            let spring = switch (from, to) {
            case (.collapsed, .hover): Self.hoverSpring
            default: Self.expandedSpring
            }
            return spring.value(
                fromValue: 0,
                toValue: 1,
                initialVelocity: 0,
                time: elapsedTime
            )
        case .easeOut:
            return UnitCurve.easeOut.value(at: elapsedTime / duration)
        }
    }

    func canComplete(generation: Int, currentGeneration: Int, state: IslandState) -> Bool {
        generation == currentGeneration && state == to
    }

    static func closeDestination(pointer: NSPoint, hoverFrame: NSRect) -> IslandState {
        WindowPositioner.containsHoverPoint(pointer, in: hoverFrame) ? .hover : .collapsed
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

    static func transitionFrame(
        from startFrame: NSRect,
        to targetFrame: NSRect,
        progress: CGFloat,
        screenFrame: NSRect
    ) -> NSRect {
        let width = startFrame.width + (targetFrame.width - startFrame.width) * progress
        let height = startFrame.height + (targetFrame.height - startFrame.height) * progress

        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    static func containsHoverPoint(_ point: NSPoint, in frame: NSRect) -> Bool {
        frame.contains(point)
            || point.y == frame.maxY && point.x >= frame.minX && point.x < frame.maxX
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
