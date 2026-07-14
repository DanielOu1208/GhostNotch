import AppKit
import SwiftUI

struct IslandExpandedView: View {
    @EnvironmentObject private var controller: IslandPanelController
    @ObservedObject var sessionState: TerminalSessionState

    let snapshot: TerminalRenderSnapshot
    let initialLastReportedResize: TerminalGridResize?
    let focusRequestID: Int
    let repaintRequestID: Int
    let headerVisible: Bool
    let terminalVisible: Bool
    let isInteractive: Bool
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (TerminalScrollEvent) -> Void
    let onMouseEvent: (TerminalMouseEvent) -> Void
    let onResize: (Int, Int, Int, Int) -> Void
    let onRestart: () -> Void
    let onCollapse: () -> Void

    private var chrome: TerminalChromePresentation {
        TerminalChromePresentation.make(sessionState: sessionState, snapshot: snapshot)
    }

    private var notchReservedHeight: CGFloat {
        IslandMetrics.notchHeight(on: WindowPositioner.notchScreen)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -4)
                .allowsHitTesting(isInteractive)

            TerminalGridSurfaceView(
                snapshot: chrome.gridSnapshot,
                initialLastReportedResize: initialLastReportedResize,
                allowsResizeReporting: controller.allowsGridResizeReporting,
                focusRequestID: focusRequestID,
                repaintRequestID: repaintRequestID,
                onInput: onInput,
                onKeyEvent: onKeyEvent,
                onScroll: onScroll,
                onMouseEvent: onMouseEvent,
                onResize: onResize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .opacity(terminalVisible ? 1 : 0)
            .offset(y: terminalVisible ? 0 : -10)
            .allowsHitTesting(isInteractive)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()

            HStack(alignment: .center, spacing: 0) {
                headerButton(systemName: "arrow.clockwise", action: onRestart)
                    .accessibilityLabel("Restart terminal")
                    .help("Restart terminal")

                headerButton(systemName: "xmark", action: onCollapse)
                    .accessibilityLabel("Collapse terminal")
                    .help("Collapse terminal")
            }
            .notchCapsuleGroupStyle()
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .frame(height: notchReservedHeight, alignment: .center)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: IslandMetrics.notchControlWidth,
                    height: IslandMetrics.notchControlHeight,
                    alignment: .center
                )
                .contentShape(Capsule())
        }
        .frame(width: IslandMetrics.notchControlWidth, height: IslandMetrics.notchControlHeight)
        .notchControlStyle()
    }
}
