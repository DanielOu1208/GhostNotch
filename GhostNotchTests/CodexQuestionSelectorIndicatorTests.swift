import XCTest

@MainActor
final class CodexQuestionSelectorIndicatorTests: XCTestCase {
    private let codex = TerminalAgentProcessIdentity(agent: .codex, processID: 101)
    private let claude = TerminalAgentProcessIdentity(agent: .claude, processID: 202)

    func testCodexUsesTitleAndStrictSelectorEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex)

        state.updateVisibleTerminalSnapshot(evidence(title: "⠋ Working", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateVisibleTerminalSnapshot(evidence(title: "Action Required", titleSequence: 2))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(evidence(
            text: "Question 1/1\n1. First\n2. Second\nunanswered\nenter to submit answer\nesc to interrupt",
            textSequence: 1,
            titleSequence: 3
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(evidence(title: "Codex", titleSequence: 4))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testClaudeUsesWorkingWaitingPreserveAndVisibleReadyEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(claude)

        state.updateVisibleTerminalSnapshot(evidence(title: "⠙ Claude", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateVisibleTerminalSnapshot(evidence(
            text: "Permission required\nAllow this command?\nYes\nNo",
            textSequence: 1,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(evidence(
            text: "Transcript viewer\nEsc to close",
            textSequence: 2,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(evidence(
            text: "❯ ",
            textSequence: 3,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testStartupGraceIgnoresEarlyEvidenceThenClassifies() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TerminalSessionState(agentStartupGrace: 3)
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateVisibleTerminalSnapshot(
            evidence(title: "⠋ Working", titleSequence: 1),
            now: start.addingTimeInterval(0.1)
        )

        state.refreshAgentStatus(now: start.addingTimeInterval(2.9))
        XCTAssertEqual(state.agentActivityState, .idle)

        state.refreshAgentStatus(now: start.addingTimeInterval(3.1))
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testEvidenceRenderedImmediatelyBeforeProcessDetectionIsNotLost() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateVisibleTerminalSnapshot(evidence(title: "Action Required", titleSequence: 1))

        state.updateDetectedAgentProcess(codex)
        state.refreshAgentStatus()

        XCTAssertEqual(state.agentActivityState, .attention)
    }

    func testPlainWorkingToReadyRequiresThreeTimedConfirmations() {
        let start = Date(timeIntervalSince1970: 2_000)
        let state = TerminalSessionState(
            agentStartupGrace: 0,
            idleConfirmationInterval: 0.1,
            idleConfirmationCap: 0.7
        )
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateVisibleTerminalSnapshot(
            evidence(title: "⠋ Working", titleSequence: 1),
            now: start
        )
        state.updateVisibleTerminalSnapshot(
            evidence(textSequence: 1, titleSequence: 2),
            now: start
        )

        XCTAssertEqual(state.agentActivityState, .working)
        XCTAssertTrue(state.agentStatusNeedsFastRefresh)

        state.refreshAgentStatus(now: start.addingTimeInterval(0.11))
        state.refreshAgentStatus(now: start.addingTimeInterval(0.22))
        XCTAssertEqual(state.agentActivityState, .working)

        state.refreshAgentStatus(now: start.addingTimeInterval(0.33))
        XCTAssertEqual(state.agentActivityState, .idle)
        XCTAssertFalse(state.agentStatusNeedsFastRefresh)
    }

    func testVisibleReadyAndProcessExitBypassPendingIdle() {
        let start = Date(timeIntervalSince1970: 3_000)
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(claude, now: start)
        state.updateVisibleTerminalSnapshot(
            evidence(title: "⠋ Claude", titleSequence: 1),
            now: start
        )

        state.updateVisibleTerminalSnapshot(
            evidence(text: "❯ ", textSequence: 1, titleSequence: 2),
            now: start
        )
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateDetectedAgentProcess(nil, now: start)
        XCTAssertNil(state.activeAgent)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testSameAgentRelaunchResetsEvidenceAndIdentity() {
        let start = Date(timeIntervalSince1970: 4_000)
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateVisibleTerminalSnapshot(
            evidence(title: "⠋ Working", titleSequence: 1),
            now: start
        )
        XCTAssertEqual(state.agentActivityState, .working)
        state.updateDetectedAgentProcess(codex, now: start.addingTimeInterval(0.5))

        state.updateDetectedAgentProcess(
            TerminalAgentProcessIdentity(agent: .codex, processID: 102),
            now: start.addingTimeInterval(1)
        )
        state.refreshAgentStatus(now: start.addingTimeInterval(1))

        XCTAssertEqual(state.activeAgentProcessIdentity?.processID, 102)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testWeakPromptLikeProseDoesNotReportWaiting() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex)
        state.updateVisibleTerminalSnapshot(evidence(
            text: "The docs ask: would you like to learn why yes and no differ?",
            textSequence: 1
        ))

        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testFreshReadyEvidenceOutranksStaleWaitingText() {
        let codexState = TerminalSessionState(agentStartupGrace: 0)
        codexState.updateDetectedAgentProcess(codex)
        codexState.updateVisibleTerminalSnapshot(evidence(
            text: "Allow command?\n› \n? for shortcuts",
            textSequence: 1,
            title: "Codex",
            titleSequence: 1
        ))
        XCTAssertEqual(codexState.agentActivityState, .idle)

        let staleSelectorState = TerminalSessionState(agentStartupGrace: 0)
        staleSelectorState.updateDetectedAgentProcess(codex)
        staleSelectorState.updateVisibleTerminalSnapshot(evidence(
            text: """
            Question 1/1
            1. First
            2. Second
            unanswered
            enter to submit answer
            esc to interrupt
            › 1+1
            ? for shortcuts
            """,
            textSequence: 1
        ))
        XCTAssertEqual(staleSelectorState.agentActivityState, .idle)

        let currentSelectorState = TerminalSessionState(agentStartupGrace: 0)
        currentSelectorState.updateDetectedAgentProcess(codex)
        currentSelectorState.updateVisibleTerminalSnapshot(evidence(
            text: "›\nAllow command?",
            textSequence: 1
        ))
        XCTAssertEqual(currentSelectorState.agentActivityState, .attention)

        let claudeState = TerminalSessionState(agentStartupGrace: 0)
        claudeState.updateDetectedAgentProcess(claude)
        claudeState.updateVisibleTerminalSnapshot(evidence(
            text: "Permission required\nAllow this command?\nYes\nNo\n❯ ",
            textSequence: 1
        ))
        XCTAssertEqual(claudeState.agentActivityState, .idle)
    }

    func testCodexQuestionSelectorDetectorRequiresStrictMarkers() {
        XCTAssertTrue(CodexTerminalUserSelectorDetector.isQuestionSelectorVisible(in: """
        Question 1/1
        1. First
        2. Second
        unanswered
        enter to submit answer
        esc to interrupt
        """))
        XCTAssertFalse(CodexTerminalUserSelectorDetector.isQuestionSelectorVisible(in: "enter to submit answer"))
    }

    private func evidence(
        text: String = "",
        textSequence: UInt64 = 0,
        title: String? = nil,
        titleSequence: UInt64 = 0,
        progress: String? = nil,
        progressSequence: UInt64 = 0
    ) -> TerminalRenderSnapshot {
        let base = TerminalRenderSnapshot.message(text, columns: 120, rows: 18)
        return TerminalRenderSnapshot(
            columns: base.columns,
            rows: base.rows,
            cells: base.cells,
            cursorColumn: base.cursorColumn,
            cursorRow: base.cursorRow,
            cursorVisible: base.cursorVisible,
            cursorBlinking: base.cursorBlinking,
            cursorStyle: base.cursorStyle,
            isAlternateScreen: base.isAlternateScreen,
            hasMouseTracking: base.hasMouseTracking,
            isBracketedPasteMode: base.isBracketedPasteMode,
            isFocusReportingMode: base.isFocusReportingMode,
            currentWorkingDirectory: base.currentWorkingDirectory,
            totalRows: base.totalRows,
            scrollbackRows: base.scrollbackRows,
            dirtyState: base.dirtyState,
            dirtyRows: base.dirtyRows,
            agentStatusText: text,
            agentStatusTextSequence: textSequence,
            terminalTitle: title,
            terminalTitleSequence: titleSequence,
            terminalProgress: progress,
            terminalProgressSequence: progressSequence
        )
    }
}
