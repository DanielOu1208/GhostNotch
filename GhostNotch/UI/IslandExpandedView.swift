import AppKit
import SwiftUI

struct IslandExpandedView: View {
    @EnvironmentObject private var controller: IslandPanelController
    @ObservedObject var sessionState: TerminalSessionState

    let snapshot: TerminalRenderSnapshot
    let initialLastReportedResize: TerminalGridResize?
    let focusRequestID: Int
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

            TerminalGridSurfaceView(
                snapshot: chrome.gridSnapshot,
                initialLastReportedResize: initialLastReportedResize,
                allowsResizeReporting: controller.allowsGridResizeReporting,
                focusRequestID: focusRequestID,
                onInput: onInput,
                onKeyEvent: onKeyEvent,
                onScroll: onScroll,
                onMouseEvent: onMouseEvent,
                onResize: onResize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer()

            headerButton(systemName: "arrow.clockwise", action: onRestart)
                .accessibilityLabel("Restart terminal")
                .help("Restart terminal")

            headerButton(systemName: "xmark", action: onCollapse)
                .accessibilityLabel("Collapse terminal")
                .help("Collapse terminal")
        }
        .padding(.horizontal, 22)
        .frame(height: notchReservedHeight, alignment: .center)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .frame(width: 28, height: 28, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
