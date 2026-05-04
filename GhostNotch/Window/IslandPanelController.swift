import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: ObservableObject {
    @Published private(set) var state: IslandState = .collapsed
    @Published private(set) var notchFillMode: NotchFillMode = .black
    @Published private(set) var motionPhase: IslandMotionPhase = .settled

    private let panel: IslandPanel
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var animationTask: Task<Void, Never>?
    private lazy var outsideClickMonitor = OutsideClickMonitor(
        shouldCollapse: { [weak self] in self?.state == .expanded },
        isPointInsidePanel: { [weak self] point in self?.panel.frame.contains(point) ?? false },
        collapse: { [weak self] in self?.collapse() }
    )

    init() {
        panel = IslandPanel(
            contentRect: WindowPositioner.frame(for: .collapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()

        let rootView = IslandRootView(
            onClick: { [weak self] in self?.expand() }
        )

        panel.contentView = IslandHostingView(rootView: rootView.environmentObject(self))
        panel.onEscape = { [weak self] in self?.collapse() }
    }

    func show() {
        outsideClickMonitor.start()
        startHoverMonitoring()
        panel.orderFrontRegardless()
    }

    func tearDown() {
        animationTask?.cancel()
        animationTask = nil
        outsideClickMonitor.stop()
        stopHoverMonitoring()
        panel.close()
    }

    func expand() {
        guard state != .expanded else {
            return
        }

        panel.shouldAcceptKeyFocus = true
        panel.styleMask.remove(.nonactivatingPanel)
        NSApp.activate()
        transition(to: .expanded)
        panel.makeKeyAndOrderFront(nil)
    }

    func collapse() {
        guard state != .collapsed else {
            return
        }

        panel.shouldAcceptKeyFocus = false
        panel.resignKey()
        panel.styleMask.insert(.nonactivatingPanel)
        transition(to: .collapsed)
    }

    func toggleNotchFillMode() {
        notchFillMode.toggle()
    }

    private func startHoverMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.refreshHoverState()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHoverState()
            }
        }
    }

    private func stopHoverMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func refreshHoverState() {
        guard state != .expanded else {
            return
        }

        setHovering(panel.frame.contains(NSEvent.mouseLocation))
    }

    private func setHovering(_ isHovering: Bool) {
        guard state != .expanded else {
            return
        }

        guard state != (isHovering ? .hover : .collapsed) else {
            return
        }

        transition(to: isHovering ? .hover : .collapsed)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
    }

    private func transition(to newState: IslandState) {
        let currentState = state
        let motion = IslandMotion(from: currentState, to: newState)

        state = newState
        motionPhase = .morphing(contentVisible: !newState.usesStagedContent)
        animatePanel(to: newState, motion: motion)
    }

    private func animatePanel(to newState: IslandState, motion: IslandMotion) {
        animationTask?.cancel()

        let startFrame = panel.frame
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let targetFrame = WindowPositioner.frame(for: newState, on: screen)

        animationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let startTime = Date.timeIntervalSinceReferenceDate
            var hasRevealedContent = !newState.usesStagedContent

            while !Task.isCancelled {
                let elapsed = Date.timeIntervalSinceReferenceDate - startTime

                if !hasRevealedContent, elapsed >= motion.contentDelay {
                    hasRevealedContent = true
                    motionPhase = .morphing(contentVisible: true)
                }

                guard elapsed < motion.duration else {
                    break
                }

                let progress = motion.progress(at: elapsed)
                let frame = IslandFrameInterpolator.frame(from: startFrame, to: targetFrame, progress: progress, screen: screen)
                panel.applyTopAttachedFrame(frame, on: screen, display: true)

                try? await Task.sleep(nanoseconds: 8_333_333)
            }

            guard !Task.isCancelled else {
                return
            }

            panel.applyTopAttachedFrame(targetFrame, on: screen, display: true)
            motionPhase = .settled
            animationTask = nil
        }
    }
}

enum IslandMotionPhase: Equatable {
    case settled
    case morphing(contentVisible: Bool)

    var contentVisible: Bool {
        switch self {
        case .settled:
            true
        case let .morphing(contentVisible):
            contentVisible
        }
    }
}

private struct IslandMotion {
    let duration: TimeInterval
    let contentDelay: TimeInterval
    let dampingRatio: Double
    let angularVelocity: Double
    let shouldReduceMotion: Bool

    init(from oldState: IslandState, to newState: IslandState) {
        shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        switch (oldState, newState) {
        case (_, .expanded):
            duration = shouldReduceMotion ? 0.18 : 0.68
            contentDelay = shouldReduceMotion ? 0.03 : 0.22
            dampingRatio = 0.54
            angularVelocity = 12
        case (.expanded, .collapsed):
            duration = shouldReduceMotion ? 0.15 : 0.5
            contentDelay = 0
            dampingRatio = 0.78
            angularVelocity = 12
        case (.collapsed, .hover):
            duration = shouldReduceMotion ? 0.14 : 0.46
            contentDelay = shouldReduceMotion ? 0.03 : 0.15
            dampingRatio = 0.62
            angularVelocity = 12.5
        case (.hover, .collapsed):
            duration = shouldReduceMotion ? 0.12 : 0.38
            contentDelay = 0
            dampingRatio = 0.76
            angularVelocity = 12.5
        default:
            duration = shouldReduceMotion ? 0.14 : 0.44
            contentDelay = newState.usesStagedContent ? 0.14 : 0
            dampingRatio = 0.6
            angularVelocity = 12.5
        }
    }

    func progress(at elapsed: TimeInterval) -> CGFloat {
        let normalizedTime = min(max(elapsed / duration, 0), 1)

        if shouldReduceMotion {
            return CGFloat(easeOutCubic(normalizedTime))
        }

        return CGFloat(springResponse(normalizedTime))
    }

    private func easeOutCubic(_ time: Double) -> Double {
        1 - pow(1 - time, 3)
    }

    private func springResponse(_ time: Double) -> Double {
        let clampedDamping = min(max(dampingRatio, 0.01), 0.99)
        let dampedVelocity = angularVelocity * sqrt(1 - clampedDamping * clampedDamping)
        let decay = exp(-clampedDamping * angularVelocity * time)
        let cosine = cos(dampedVelocity * time)
        let sine = sin(dampedVelocity * time)
        let dampingAdjustment = clampedDamping / sqrt(1 - clampedDamping * clampedDamping)

        return 1 - decay * (cosine + dampingAdjustment * sine)
    }
}

private enum IslandFrameInterpolator {
    static func frame(from startFrame: NSRect, to targetFrame: NSRect, progress: CGFloat, screen: NSScreen) -> NSRect {
        let width = interpolate(from: startFrame.width, to: targetFrame.width, progress: progress)
        let height = interpolate(from: startFrame.height, to: targetFrame.height, progress: progress)
        let scale = screen.backingScaleFactor
        let alignedWidth = alignToPixel(width, scale: scale)
        let alignedHeight = alignToPixel(height, scale: scale)
        let centerX = alignToPixel(targetFrame.midX, scale: scale)
        let topY = alignToPixel(screen.frame.maxY + IslandMetrics.topAttachmentOverscan, scale: scale)
        let origin = NSPoint(x: centerX - alignedWidth / 2, y: topY - alignedHeight)

        return NSRect(origin: origin, size: NSSize(width: alignedWidth, height: alignedHeight))
    }

    private static func interpolate(from startValue: CGFloat, to targetValue: CGFloat, progress: CGFloat) -> CGFloat {
        startValue + (targetValue - startValue) * progress
    }

    private static func alignToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

private extension IslandPanel {
    func applyTopAttachedFrame(_ frame: NSRect, on screen: NSScreen, display: Bool) {
        let topY = screen.frame.maxY + IslandMetrics.topAttachmentOverscan

        setFrame(frame, display: display)
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: topY))
    }
}

private extension IslandState {
    var usesStagedContent: Bool {
        switch self {
        case .collapsed:
            false
        case .hover, .expanded:
            true
        }
    }
}
