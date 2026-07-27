import XCTest

@MainActor
final class CodexQuestionSelectorIndicatorTests: XCTestCase {
    private let codex = TerminalAgentProcessIdentity(agent: .codex, processID: 101)
    private let claude = TerminalAgentProcessIdentity(agent: .claude, processID: 202)
    private let opencode = TerminalAgentProcessIdentity(agent: .opencode, processID: 303)
    private let cursor = TerminalAgentProcessIdentity(agent: .cursor, processID: 404)
    private let omp = TerminalAgentProcessIdentity(agent: .omp, processID: 505)
    private let pi = TerminalAgentProcessIdentity(agent: .pi, processID: 606)
    private let droid = TerminalAgentProcessIdentity(agent: .droid, processID: 707)

    func testCodexUsesTitleAndStrictSelectorEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex)

        state.updateAgentStatusEvidence(evidence(title: "⠋ Working", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(title: "Action Required", titleSequence: 2))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(
            text: "Question 1/1\n1. First\n2. Second\nunanswered\nenter to submit answer\nesc to interrupt",
            textSequence: 1,
            titleSequence: 3
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(title: "Codex", titleSequence: 4))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testClaudeUsesWorkingWaitingPreserveAndVisibleReadyEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(claude)

        state.updateAgentStatusEvidence(evidence(title: "⠙ Claude", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(
            text: "Permission required\nAllow this command?\nYes\nNo",
            textSequence: 1,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(
            text: "Transcript viewer\nEsc to close",
            textSequence: 2,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(
            text: "❯ ",
            textSequence: 3,
            titleSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testOpenCodeUsesThinkingPermissionAndComposerEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(opencode)

        state.updateAgentStatusEvidence(evidence(text: "Thinking: inspect repository", textSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(
            text: "Permission required\nAllow once\nAllow always\nReject",
            textSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(text: ">", textSequence: 3))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testCursorUsesActivityApprovalAndComposerEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(cursor)

        state.updateAgentStatusEvidence(evidence(text: "⠋ Working", textSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(
            text: "Approve running this command? [Y/N]\nReject with N",
            textSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(text: ">", textSequence: 3))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testOMPUsesTerminalTitleAsPrimaryStatusContract() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(omp)

        state.updateAgentStatusEvidence(evidence(title: "π ⠋ GhostNotch", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(title: "π ! GhostNotch", titleSequence: 2))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(title: "π > GhostNotch", titleSequence: 3))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testPiUsesWorkingTrustAndComposerEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(pi)

        state.updateAgentStatusEvidence(evidence(text: "Working...", textSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(
            text: "Trust this project?\nYes\nNo",
            textSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(text: ">", textSequence: 3))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testDroidUsesActivityPermissionAndComposerEvidence() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(droid)

        state.updateAgentStatusEvidence(evidence(text: "Thinking", textSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.updateAgentStatusEvidence(evidence(
            text: "Permission required\nAccept change\nReject change",
            textSequence: 2
        ))
        XCTAssertEqual(state.agentActivityState, .attention)

        state.updateAgentStatusEvidence(evidence(text: ">", textSequence: 3))
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testStartupGraceIgnoresEarlyEvidenceThenClassifies() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TerminalSessionState(agentStartupGrace: 3)
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateAgentStatusEvidence(
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
        state.updateAgentStatusEvidence(evidence(title: "Action Required", titleSequence: 1))

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
        state.updateAgentStatusEvidence(
            evidence(title: "⠋ Working", titleSequence: 1),
            now: start
        )
        state.updateAgentStatusEvidence(
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
        state.updateAgentStatusEvidence(
            evidence(title: "⠋ Claude", titleSequence: 1),
            now: start
        )

        state.updateAgentStatusEvidence(
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
        state.updateAgentStatusEvidence(
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

    func testEvidenceAfterLastPollDoesNotCrossIntoReplacementProcess() {
        let start = Date(timeIntervalSince1970: 4_500)
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateAgentStatusEvidence(
            evidence(title: "Codex", titleSequence: 1),
            now: start
        )
        state.updateDetectedAgentProcess(codex, now: start.addingTimeInterval(0.1))
        state.updateAgentStatusEvidence(
            evidence(title: "⠋ Working", titleSequence: 2),
            now: start.addingTimeInterval(0.2)
        )

        state.updateDetectedAgentProcess(claude, now: start.addingTimeInterval(0.3))
        state.refreshAgentStatus(now: start.addingTimeInterval(0.3))

        XCTAssertEqual(state.activeAgent, .claude)
        XCTAssertEqual(state.agentActivityState, .idle)

        state.updateAgentStatusEvidence(
            evidence(title: "⠙ Claude", titleSequence: 3),
            now: start.addingTimeInterval(0.4)
        )
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testEvidenceAfterExitButBeforeRediscoveryBelongsToNewProcess() {
        let start = Date(timeIntervalSince1970: 4_600)
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex, now: start)
        state.updateAgentStatusEvidence(evidence(title: "Codex", titleSequence: 1), now: start)
        state.updateDetectedAgentProcess(nil, now: start.addingTimeInterval(0.1))

        state.updateAgentStatusEvidence(
            evidence(title: "Action Required", titleSequence: 2),
            now: start.addingTimeInterval(0.2)
        )
        state.updateDetectedAgentProcess(codex, now: start.addingTimeInterval(0.3))
        state.refreshAgentStatus(now: start.addingTimeInterval(0.3))

        XCTAssertEqual(state.agentActivityState, .attention)
    }

    func testEvidenceSeenDuringNoAgentPollDoesNotBelongToLaterProcess() {
        let start = Date(timeIntervalSince1970: 4_700)
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateAgentStatusEvidence(
            evidence(title: "⠋ Old output", titleSequence: 1),
            now: start
        )
        state.updateDetectedAgentProcess(nil, now: start.addingTimeInterval(0.1))

        state.updateDetectedAgentProcess(codex, now: start.addingTimeInterval(0.2))
        state.refreshAgentStatus(now: start.addingTimeInterval(0.2))

        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testPromptsOutsidePhysicalBottomEightRowsDoNotReportWaiting() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex)
        state.updateAgentStatusEvidence(evidence(
            text: "Allow command?\n" + String(repeating: "\n", count: 8),
            textSequence: 1
        ))

        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testExistingBroadAttentionPromptPhrasesRemainSupported() {
        let codexPrompts = [
            "enter to submit answer",
            "enter to submit all",
            "allow command?",
            "press enter to confirm\nesc to go back",
            "do you want to continue?\n[y/n]",
            "would you like to continue?\nyes (y)",
        ]
        let claudePrompts = [
            "enter to select\nesc to cancel",
            "do you want to proceed?",
            "permission required\nallow",
            "would you like to continue?\nyes\nno",
        ]

        for (index, prompt) in codexPrompts.enumerated() {
            let state = TerminalSessionState(agentStartupGrace: 0)
            state.updateDetectedAgentProcess(codex)
            state.updateAgentStatusEvidence(evidence(text: prompt, textSequence: UInt64(index + 1)))
            XCTAssertEqual(state.agentActivityState, .attention, prompt)
        }

        for (index, prompt) in claudePrompts.enumerated() {
            let state = TerminalSessionState(agentStartupGrace: 0)
            state.updateDetectedAgentProcess(claude)
            state.updateAgentStatusEvidence(evidence(text: prompt, textSequence: UInt64(index + 1)))
            XCTAssertEqual(state.agentActivityState, .attention, prompt)
        }
    }

    func testWeakPromptLikeProseDoesNotReportWaiting() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        state.updateDetectedAgentProcess(codex)
        state.updateAgentStatusEvidence(evidence(
            text: "The docs ask: would you like to learn why yes and no differ?",
            textSequence: 1
        ))

        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testFreshReadyEvidenceOutranksStaleWaitingText() {
        let codexState = TerminalSessionState(agentStartupGrace: 0)
        codexState.updateDetectedAgentProcess(codex)
        codexState.updateAgentStatusEvidence(evidence(
            text: "Allow command?\n› \n? for shortcuts",
            textSequence: 1,
            title: "Codex",
            titleSequence: 1
        ))
        XCTAssertEqual(codexState.agentActivityState, .idle)

        let staleSelectorState = TerminalSessionState(agentStartupGrace: 0)
        staleSelectorState.updateDetectedAgentProcess(codex)
        staleSelectorState.updateAgentStatusEvidence(evidence(
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
        currentSelectorState.updateAgentStatusEvidence(evidence(
            text: "›\nAllow command?",
            textSequence: 1
        ))
        XCTAssertEqual(currentSelectorState.agentActivityState, .attention)

        let claudeState = TerminalSessionState(agentStartupGrace: 0)
        claudeState.updateDetectedAgentProcess(claude)
        claudeState.updateAgentStatusEvidence(evidence(
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
    ) -> TerminalAgentStatusEvidence {
        TerminalAgentStatusEvidence(
            text: text,
            textSequence: textSequence,
            title: title,
            titleSequence: titleSequence,
            progress: progress,
            progressSequence: progressSequence
        )
    }
}
