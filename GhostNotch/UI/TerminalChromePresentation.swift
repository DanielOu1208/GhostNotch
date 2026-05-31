struct TerminalChromePresentation {
    let gridSnapshot: TerminalRenderSnapshot

    @MainActor
    static func make(
        sessionState: TerminalSessionState,
        snapshot: TerminalRenderSnapshot
    ) -> TerminalChromePresentation {
        if let lastError = sessionState.lastError {
            return TerminalChromePresentation(
                gridSnapshot: .message("GhostNotch terminal error:\n\(lastError)\n")
            )
        }

        switch sessionState.phase {
        case .running:
            return TerminalChromePresentation(
                gridSnapshot: snapshot
            )
        case .starting:
            let gridSnapshot: TerminalRenderSnapshot
            if sessionState.hasReceivedOutput {
                gridSnapshot = snapshot
            } else {
                gridSnapshot = .message("Starting shell...\n")
            }
            return TerminalChromePresentation(
                gridSnapshot: gridSnapshot
            )
        case .stopped:
            return TerminalChromePresentation(
                gridSnapshot: .message("Shell stopped.\n")
            )
        case .failed:
            return TerminalChromePresentation(
                gridSnapshot: .message("Shell stopped.\n")
            )
        }
    }
}
