import AppKit
import SwiftUI

struct IslandExpandedView: View {
    @ObservedObject var sessionState: TerminalSessionState

    let snapshot: TerminalRenderSnapshot
    let initialLastReportedResize: TerminalGridResize?
    let allowsResizeReporting: Bool
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (Int) -> Void
    let onResize: (Int, Int, Int, Int) -> Void
    let onRestart: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            header

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            TerminalGridSurfaceView(
                snapshot: terminalSnapshot,
                initialLastReportedResize: initialLastReportedResize,
                allowsResizeReporting: allowsResizeReporting,
                focusRequestID: focusRequestID,
                onInput: onInput,
                onKeyEvent: onKeyEvent,
                onScroll: onScroll,
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
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.45), radius: 5)

            Text("GhostNotch")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text(statusText)
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

    private var terminalSnapshot: TerminalRenderSnapshot {
        if let lastError = sessionState.lastError {
            return .message("GhostNotch terminal error:\n\(lastError)\n")
        }

        switch sessionState.phase {
        case .running:
            return snapshot
        case .starting:
            if sessionState.outputText.isEmpty {
                return .message("Starting shell...\n")
            }
            return snapshot
        case .stopped:
            return .message("Shell stopped.\n")
        case .failed:
            return .message("Shell stopped.\n")
        }
    }

    private var statusColor: Color {
        sessionState.phase == .running ? .green : .orange
    }

    private var statusText: String {
        if sessionState.lastError != nil {
            return "terminal error"
        }

        switch sessionState.phase {
        case .stopped:
            return "shell stopped"
        case .starting:
            return "starting shell"
        case .running:
            return "default shell"
        case .failed:
            return "terminal error"
        }
    }
}
