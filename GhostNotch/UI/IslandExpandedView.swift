import AppKit
import SwiftUI

struct IslandExpandedView: View {
    @ObservedObject var sessionState: TerminalSessionState

    let snapshot: TerminalRenderSnapshot
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (Int) -> Void
    let onResize: (Int, Int) -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            header

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            TerminalGridSurfaceView(
                snapshot: terminalSnapshot,
                focusRequestID: focusRequestID,
                onInput: onInput,
                onKeyEvent: onKeyEvent,
                onScroll: onScroll,
                onResize: onResize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
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

            Button(action: onCollapse) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }

    private var terminalSnapshot: TerminalRenderSnapshot {
        if let lastError = sessionState.lastError {
            return .message("GhostNotch terminal error:\n\(lastError)\n")
        }

        if sessionState.outputText.isEmpty {
            return .message(sessionState.isRunning ? "Starting shell...\n" : "Shell stopped.\n")
        }

        return snapshot
    }

    private var statusColor: Color {
        sessionState.lastError == nil && sessionState.isRunning ? .green : .orange
    }

    private var statusText: String {
        if sessionState.lastError != nil {
            return "terminal error"
        }

        return sessionState.isRunning ? "default shell" : "starting shell"
    }
}
