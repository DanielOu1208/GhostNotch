import SwiftUI

struct TerminalChromePresentation {
    let gridSnapshot: TerminalRenderSnapshot
    let statusText: String
    let statusColor: Color

    @MainActor
    static func make(
        sessionState: TerminalSessionState,
        snapshot: TerminalRenderSnapshot
    ) -> TerminalChromePresentation {
        if let lastError = sessionState.lastError {
            return TerminalChromePresentation(
                gridSnapshot: .message("GhostNotch terminal error:\n\(lastError)\n"),
                statusText: "terminal error",
                statusColor: .orange
            )
        }

        switch sessionState.phase {
        case .running:
            return TerminalChromePresentation(
                gridSnapshot: snapshot,
                statusText: "default shell",
                statusColor: .green
            )
        case .starting:
            let gridSnapshot: TerminalRenderSnapshot
            if sessionState.outputText.isEmpty {
                gridSnapshot = .message("Starting shell...\n")
            } else {
                gridSnapshot = snapshot
            }
            return TerminalChromePresentation(
                gridSnapshot: gridSnapshot,
                statusText: "starting shell",
                statusColor: .orange
            )
        case .stopped:
            return TerminalChromePresentation(
                gridSnapshot: .message("Shell stopped.\n"),
                statusText: "shell stopped",
                statusColor: .orange
            )
        case .failed:
            return TerminalChromePresentation(
                gridSnapshot: .message("Shell stopped.\n"),
                statusText: "terminal error",
                statusColor: .orange
            )
        }
    }
}
