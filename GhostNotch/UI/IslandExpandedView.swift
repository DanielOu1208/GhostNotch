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

    var body: some View {
        VStack(spacing: 0) {

            header

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

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
            .padding(.top, 4)
            .padding(.bottom, 5)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(chrome.statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: chrome.statusColor.opacity(0.45), radius: 5)

            Text("GhostNotch")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text(chrome.statusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))

            Spacer()

            headerButton(systemName: "arrow.clockwise", action: onRestart)
                .accessibilityLabel("Restart terminal")
                .help("Restart terminal")

            headerButton(systemName: "xmark", action: onCollapse)
                .accessibilityLabel("Collapse terminal")
                .help("Collapse terminal")
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
