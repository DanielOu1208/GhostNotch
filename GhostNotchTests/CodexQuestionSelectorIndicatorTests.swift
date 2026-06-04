import Foundation
import XCTest

@MainActor
final class CodexQuestionSelectorIndicatorTests: XCTestCase {
    func testCodexQuestionSelectorDetectorRequiresStrictMarkers() {
        let questionSelectorText = """
        Question 1/1 (1 unanswered)
        Which hover animation direction should the plan use?

          1. Terminal cursor
        > 2. Status breath
          3. Subtle entrance

        tab to add notes | enter to submit answer | esc to interrupt
        """

        XCTAssertTrue(CodexTerminalQuestionSelectorDetector.isQuestionSelectorVisible(in: questionSelectorText))
        XCTAssertFalse(CodexTerminalQuestionSelectorDetector.isQuestionSelectorVisible(in: "Question 1/1\n1. Not enough\n2. Markers"))
        XCTAssertFalse(CodexTerminalQuestionSelectorDetector.isQuestionSelectorVisible(in: "enter to submit answer\nesc to interrupt\nno question marker"))
    }

    func testCodexVisibleQuestionSelectorOverridesWorkingStateToIdle() {
        let state = TerminalSessionState()
        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date(),
                isLegacy: false
            )
        )

        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())

        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testPermissionRequestOverridesVisibleQuestionSelectorToAttention() {
        let state = TerminalSessionState()
        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date(),
                isLegacy: false
            )
        )
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .attention,
                event: "PermissionRequest",
                timestamp: Date().addingTimeInterval(1),
                isLegacy: false
            )
        )

        XCTAssertEqual(state.agentActivityState, .attention)
    }

    func testNonCodexAndNonQuestionSelectorSnapshotsDoNotOverrideHookState() {
        let state = TerminalSessionState()
        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .claude,
                state: .working,
                event: "ElicitationResult",
                timestamp: Date(),
                isLegacy: false
            )
        )

        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date(),
                isLegacy: false
            )
        )
        state.updateVisibleTerminalSnapshot(.message("Question 1/1\nworking output", columns: 120, rows: 8))

        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testFreshCodexWorkingHooksKeepVisibleQuestionSelectorIdle() {
        let state = TerminalSessionState()
        let firstRecord = TerminalAgentActivityRecord(
            agent: .codex,
            state: .working,
            event: "PreToolUse",
            timestamp: Date(),
            isLegacy: false
        )
        state.updateAgentActivityRecord(firstRecord)
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PostToolUse",
                timestamp: Date().addingTimeInterval(1),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date().addingTimeInterval(2),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateVisibleTerminalSnapshot(.message("Codex is working", columns: 120, rows: 12))
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testStopFailureAndClearOutputClearCodexQuestionSelectorOverride() {
        let state = TerminalSessionState()
        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date()))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markStopped()
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date().addingTimeInterval(1)))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .idle)

        state.recordError("boom")
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date().addingTimeInterval(2)))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .idle)

        state.clearOutput()
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    private func codexWorkingRecord(timestamp: Date) -> TerminalAgentActivityRecord {
        TerminalAgentActivityRecord(
            agent: .codex,
            state: .working,
            event: "PreToolUse",
            timestamp: timestamp,
            isLegacy: false
        )
    }

    private func codexQuestionSelectorSnapshot(
        question: String = "Which hover animation direction should the plan use?"
    ) -> TerminalRenderSnapshot {
        TerminalRenderSnapshot.message(
            """
            Question 1/1 (1 unanswered)
            \(question)

              1. Terminal cursor
            > 2. Status breath
              3. Subtle entrance

            tab to add notes | enter to submit answer | esc to interrupt
            """,
            columns: 120,
            rows: 12
        )
    }
}
