import AppKit
import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject private var controller: IslandPanelController

    let onClick: () -> Void

    var body: some View {
        ZStack {
            NotchBackground(state: controller.state, fillMode: controller.notchFillMode)

            islandContent
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

    @ViewBuilder
    private var islandContent: some View {
        switch controller.state {
        case .collapsed, .hover:
            IslandIndicatorView(
                sessionState: controller.terminalState,
                presetStore: controller.agentPresetStore,
                isHovering: controller.state == .hover,
                selectedDirectoryPresetID: controller.selectedLaunchDirectoryPresetID,
                onSelectDirectory: controller.selectLaunchDirectory,
                onLaunchAgent: controller.launchAgent
            )
        case .expanded:
            IslandExpandedView(
                sessionState: controller.terminalState,
                snapshot: controller.terminalSnapshot,
                initialLastReportedResize: controller.lastAppliedGridResize,
                focusRequestID: controller.terminalFocusRequestID,
                repaintRequestID: controller.terminalSurfaceRepaintRequestID,
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
}

private struct NotchControlStyle: ViewModifier {
    @State private var isHovering = false

    let isSelected: Bool

    func body(content: Content) -> some View {
        Group {
            if isSelected {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            } else if isHovering {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            } else {
                content
                    .buttonStyle(.plain)
            }
        }
        .onHover { isHovering = $0 }
    }
}

extension View {
    func notchControlStyle(isSelected: Bool = false) -> some View {
        modifier(NotchControlStyle(isSelected: isSelected))
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
    let state: IslandState
    let fillMode: NotchFillMode

    var body: some View {
        NotchExtensionShape(cornerRadius: cornerRadius)
            .fill(fillMode.color)
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
    let cornerRadius: CGFloat

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
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

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
