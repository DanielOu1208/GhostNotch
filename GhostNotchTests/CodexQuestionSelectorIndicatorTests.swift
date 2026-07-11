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

        XCTAssertTrue(CodexTerminalUserSelectorDetector.isQuestionSelectorVisible(in: questionSelectorText))
        XCTAssertTrue(CodexTerminalUserSelectorDetector.isUserSelectorVisible(in: questionSelectorText))
        XCTAssertFalse(CodexTerminalUserSelectorDetector.isQuestionSelectorVisible(in: "Question 1/1\n1. Not enough\n2. Markers"))
        XCTAssertFalse(CodexTerminalUserSelectorDetector.isQuestionSelectorVisible(in: "enter to submit answer\nesc to interrupt\nno question marker"))
    }

    func testCodexPlanImplementationSelectorDetectorRequiresStrictMarkers() {
        let planSelectorText = """
        Implement this plan?

        > 1. Yes, implement this plan          Switch to Default and start coding.
          2. Yes, clear context and implement  Fresh thread. Context: 6% used.
          3. No, stay in Plan mode             Continue planning with the model.

        Press enter to confirm or esc to go back
        """

        XCTAssertTrue(CodexTerminalUserSelectorDetector.isPlanImplementationSelectorVisible(in: planSelectorText))
        XCTAssertTrue(CodexTerminalUserSelectorDetector.isUserSelectorVisible(in: planSelectorText))
        XCTAssertFalse(
            CodexTerminalUserSelectorDetector.isPlanImplementationSelectorVisible(
                in: "Implement this plan?\n1. Yes\n2. No\nPress enter to confirm or esc to go back"
            )
        )
        XCTAssertFalse(
            CodexTerminalUserSelectorDetector.isPlanImplementationSelectorVisible(
                in: "The implementation plan says to press enter to confirm or esc to go back later."
            )
        )
    }

    private let selectorDwellNanoseconds: UInt64 = 20_000_000

    func testCodexVisibleQuestionSelectorOverridesWorkingStateToAttention() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
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

        XCTAssertEqual(state.agentActivityState, .working)
        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)
    }

    func testCodexPlanImplementationSelectorOverridesWorkingStateToAttention() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PostToolUse",
                timestamp: Date(),
                isLegacy: false
            )
        )

        state.updateVisibleTerminalSnapshot(codexPlanImplementationSelectorSnapshot())

        XCTAssertEqual(state.agentActivityState, .working)
        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)
    }

    func testPermissionRequestOverridesVisibleQuestionSelectorToAttention() {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
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
        XCTAssertEqual(state.agentActivityState, .working)

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
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
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
        state.updateVisibleTerminalSnapshot(codexPlanImplementationSelectorSnapshot())
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

    func testNonCodexSnapshotsSkipVisibleTextExtraction() {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        var didExtractVisibleText = false

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .claude,
                state: .working,
                event: "ElicitationResult",
                timestamp: Date(),
                isLegacy: false
            )
        )
        state.updateVisibleTerminalSnapshot(.empty(), visibleText: {
            didExtractVisibleText = true
            return ""
        })

        XCTAssertFalse(didExtractVisibleText)

        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date()))
        state.updateVisibleTerminalSnapshot(.empty(), visibleText: {
            didExtractVisibleText = true
            return ""
        })

        XCTAssertTrue(didExtractVisibleText)
    }

    func testClaudeAttentionReturnsToWorkingThenIdleFromHooks() {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        state.markRunning()

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .claude,
                state: .attention,
                event: "PermissionRequest",
                timestamp: Date(),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .claude,
                state: .working,
                event: "PreToolUse",
                timestamp: Date().addingTimeInterval(1),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .claude,
                state: .idle,
                event: "Stop",
                timestamp: Date().addingTimeInterval(2),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testFreshCodexWorkingHooksKeepVisibleQuestionSelectorAttention() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        let firstRecord = TerminalAgentActivityRecord(
            agent: .codex,
            state: .working,
            event: "PreToolUse",
            timestamp: Date(),
            isLegacy: false
        )
        state.updateAgentActivityRecord(firstRecord)
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PostToolUse",
                timestamp: Date().addingTimeInterval(1),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .working)

        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date().addingTimeInterval(2),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(.message("Codex is working", columns: 120, rows: 12))
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testFreshCodexWorkingHooksKeepVisiblePlanImplementationSelectorAttention() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date()))
        state.updateVisibleTerminalSnapshot(codexPlanImplementationSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PostToolUse",
                timestamp: Date().addingTimeInterval(1),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .working)

        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentActivityRecord(
            TerminalAgentActivityRecord(
                agent: .codex,
                state: .working,
                event: "PreToolUse",
                timestamp: Date().addingTimeInterval(2),
                isLegacy: false
            )
        )
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateVisibleTerminalSnapshot(.message("Codex is working", columns: 120, rows: 12))
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testTransientCodexUserSelectorClearsBeforeDwellWithoutAttention() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date()))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateVisibleTerminalSnapshot(.message("Codex is working", columns: 120, rows: 12))
        try await waitForSelectorDwell()

        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testStopFailureAndClearOutputClearCodexUserSelectorOverride() async throws {
        let state = TerminalSessionState(codexSelectorDwellNanoseconds: selectorDwellNanoseconds)
        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date()))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)

        state.markStopped()
        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date().addingTimeInterval(1)))
        state.updateVisibleTerminalSnapshot(codexPlanImplementationSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)
        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)

        state.recordError("boom")
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateAgentActivityRecord(codexWorkingRecord(timestamp: Date().addingTimeInterval(2)))
        state.updateVisibleTerminalSnapshot(codexQuestionSelectorSnapshot())
        XCTAssertEqual(state.agentActivityState, .working)
        try await waitForSelectorDwell()
        XCTAssertEqual(state.agentActivityState, .attention)

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

    private func waitForSelectorDwell() async throws {
        try await Task.sleep(nanoseconds: selectorDwellNanoseconds + 30_000_000)
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

    private func codexPlanImplementationSelectorSnapshot() -> TerminalRenderSnapshot {
        TerminalRenderSnapshot.message(
            """
            Implement this plan?

            > 1. Yes, implement this plan          Switch to Default and start coding.
              2. Yes, clear context and implement  Fresh thread. Context: 6% used.
              3. No, stay in Plan mode             Continue planning with the model.

            Press enter to confirm or esc to go back
            """,
            columns: 120,
            rows: 10
        )
    }
}
