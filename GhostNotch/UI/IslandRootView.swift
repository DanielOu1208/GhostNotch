import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject private var controller: IslandPanelController

    let onClick: () -> Void

    var body: some View {
        ZStack {
            NotchBackground(state: controller.state, fillMode: controller.notchFillMode)

            switch controller.state {
            case .collapsed, .hover:
                IslandIndicatorView(isHovering: controller.state == .hover)
            case .expanded:
                IslandExpandedView(
                    sessionState: controller.terminalState,
                    snapshot: controller.terminalSnapshot,
                    focusRequestID: controller.terminalFocusRequestID,
                    onInput: controller.writeToTerminal,
                    onKeyEvent: controller.sendTerminalKeyEvent,
                    onScroll: controller.scrollTerminal,
                    onResize: controller.resizeTerminal,
                    onRestart: controller.restartTerminal,
                    onCollapse: controller.collapse
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
    }
}

private struct NotchBackground: View {
    let state: IslandState
    let fillMode: NotchFillMode

    var body: some View {
        NotchExtensionShape(cornerRadius: cornerRadius)
            .fill(fillMode.color)
            .shadow(color: .black.opacity(state == .expanded ? 0.32 : 0), radius: state == .expanded ? 22 : 0, y: state == .expanded ? 14 : 0)
    }

    private var cornerRadius: CGFloat {
        state.notchCornerRadius
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
