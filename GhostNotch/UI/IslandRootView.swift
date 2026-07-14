import AppKit
import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject private var controller: IslandPanelController

    let onClick: () -> Void

    var body: some View {
        ZStack {
            NotchBackground(state: controller.state, fillMode: controller.notchFillMode)

            ZStack {
                if controller.showsCompactContent {
                    compactContent
                        .opacity(controller.compactContentVisible ? 1 : 0)
                        .allowsHitTesting(
                            controller.compactContentVisible && controller.transitionPlan == nil
                        )
                }

                if controller.showsExpandedContent {
                    expandedContent
                }
            }
                .clipShape(notchShape)

            NotchRimOverlay(state: controller.state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .modifier(CollapsedIslandTapToExpand(onClick: onClick, isEnabled: controller.state != .expanded))
    }

    private var notchShape: NotchExtensionShape {
        NotchExtensionShape(cornerRadius: controller.state.notchCornerRadius)
    }

    private var compactContent: some View {
        IslandIndicatorView(
            sessionState: controller.terminalState,
            presetStore: controller.agentPresetStore,
            isHovering: controller.compactPresentationState == .hover,
            selectedDirectoryPresetID: controller.selectedLaunchDirectoryPresetID,
            onSelectDirectory: controller.selectLaunchDirectory,
            onLaunchAgent: controller.launchAgent
        )
    }

    private var expandedContent: some View {
        IslandExpandedView(
            sessionState: controller.terminalState,
            snapshot: controller.terminalSnapshot,
            initialLastReportedResize: controller.lastAppliedGridResize,
            focusRequestID: controller.terminalFocusRequestID,
            repaintRequestID: controller.terminalSurfaceRepaintRequestID,
            headerVisible: controller.expandedHeaderVisible,
            terminalVisible: controller.expandedTerminalVisible,
            isInteractive: controller.expandedContentIsInteractive,
            onInput: controller.writeToTerminal,
            onKeyEvent: controller.sendTerminalKeyEvent,
            onScroll: controller.handleTerminalScrollWheel,
            onMouseEvent: controller.handleTerminalMouseEvent,
            onResize: controller.resizeTerminal,
            onRestart: controller.restartTerminal,
            onCollapse: controller.collapse
        )
    }
}

private struct NotchControlStyle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background {
                if isHovering {
                    Color.clear
                        .frame(
                            width: IslandMetrics.notchControlWidth - IslandMetrics.notchCapsuleGroupInset * 2,
                            height: IslandMetrics.notchControlHeight - IslandMetrics.notchCapsuleGroupInset * 2
                        )
                        .glassEffect(
                            .regular.tint(.white.opacity(0.14)).interactive(),
                            in: Capsule()
                        )
                        .glassEffectTransition(.materialize)
                        .clipShape(Capsule())
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func notchControlStyle() -> some View {
        modifier(NotchControlStyle())
    }

    func notchCapsuleGroupStyle() -> some View {
        modifier(NotchCapsuleGroupStyle())
    }
}

private struct NotchCapsuleGroupStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(IslandMetrics.notchCapsuleGroupInset)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private struct CollapsedIslandTapToExpand: ViewModifier {
    let onClick: () -> Void
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onClick)
        } else {
            content
        }
    }
}

private struct NotchBackground: View {
    @Environment(\.displayScale) private var displayScale

    let state: IslandState
    let fillMode: NotchFillMode

    var body: some View {
        ZStack(alignment: .top) {
            NotchExtensionShape(cornerRadius: cornerRadius)
                .fill(fillMode.color)

            Rectangle()
                .fill(fillMode.color)
                .frame(height: 1 / max(displayScale, 1))
        }
    }

    private var cornerRadius: CGFloat {
        state.notchCornerRadius
    }
}

private struct NotchRimOverlay: View {
    @Environment(\.displayScale) private var displayScale

    let state: IslandState

    private var rimLineWidth: CGFloat {
        2 / max(displayScale, 1)
    }

    var body: some View {
        if state.showsNotchRim {
            NotchRimShape(cornerRadius: state.notchCornerRadius, lineWidth: rimLineWidth)
                .stroke(Color(nsColor: .separatorColor), lineWidth: rimLineWidth)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

enum NotchFillMode: Equatable {
    case black
    case darkGray

    mutating func toggle() {
        self = self == .black ? .darkGray : .black
    }

    var color: Color {
        switch self {
        case .black:
            .black
        case .darkGray:
            Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }
}

private extension IslandState {
    var notchCornerRadius: CGFloat {
        switch self {
        case .collapsed:
            14
        case .hover:
            14
        case .expanded:
            18
        }
    }

    var showsNotchRim: Bool {
        switch self {
        case .collapsed:
            false
        case .hover, .expanded:
            true
        }
    }

}

private struct NotchExtensionShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control: CGPoint(x: minX, y: maxY)
        )
        path.closeSubpath()

        return path
    }
}

private struct NotchRimShape: Shape {
    var cornerRadius: CGFloat
    let lineWidth: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let radius = min(max(cornerRadius - inset, 0), rect.width / 2, rect.height)
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY
        let maxY = rect.maxY - inset

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: minX + radius, y: maxY),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: maxY - radius),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX, y: minY))

        return path
    }
}
