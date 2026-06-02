import Combine
import XCTest

@MainActor
final class TerminalSessionTests: XCTestCase {
    func testPTYEnvironmentForcesConservativeTermType() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "SHELL": "/bin/sh",
            "TERM": "xterm-ghostty",
            "TERM_PROGRAM": "Ghostty",
            "TERM_PROGRAM_VERSION": "1.0",
            "GHOSTNOTCH_VERSION": "stale",
            "COLORTERM": "falsecolor",
            "GHOSTNOTCH_RESOURCES_DIR": "/tmp/old",
            "PATH": "/usr/bin:/bin",
        ])

        XCTAssertEqual(environment["TERM"], PTYProcess.defaultTerminalType)
        XCTAssertEqual(environment["TERM_PROGRAM"], PTYProcess.termProgram)
        XCTAssertEqual(environment["TERM_PROGRAM_VERSION"], PTYProcess.termProgramVersion)
        XCTAssertEqual(environment["GHOSTNOTCH_VERSION"], PTYProcess.termProgramVersion)
        XCTAssertEqual(environment["COLORTERM"], PTYProcess.defaultColorTerminal)
        XCTAssertEqual(environment["GHOSTNOTCH_RESOURCES_DIR"]?.hasSuffix("/ShellIntegration"), true)
        XCTAssertEqual(environment["SHELL"], "/bin/sh")
        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"
        )
    }

    func testPTYEnvironmentAddsDeveloperPathsAndPreservesInheritedPathOrder() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "PATH": "/Users/danielou/.npm-global/bin:/custom/bin:/usr/bin",
        ])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin:/Users/danielou/.npm-global/bin:/custom/bin:/usr/bin"
        )
    }

    func testPTYEnvironmentRemovesDuplicatePathEntries() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "PATH": "/usr/local/bin:/custom/bin:/usr/local/bin:/custom/bin:/bin",
        ])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin:/custom/bin:/bin"
        )
    }

    func testPTYEnvironmentDefaultsPathWhenInheritedPathIsBlank() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "PATH": "::",
        ])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    func testPTYEnvironmentDefaultsPathWhenInheritedPathIsMissing() {
        let environment = PTYProcess.terminalEnvironment(from: [:])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    func testPTYEnvironmentDefaultsToUTF8LocaleWhenInheritedLocaleIsC() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "LANG": "",
            "LC_CTYPE": "C",
            "LC_ALL": "POSIX",
        ])

        XCTAssertEqual(environment["LANG"], PTYProcess.defaultUTF8Locale)
        XCTAssertEqual(environment["LC_CTYPE"], PTYProcess.defaultUTF8Locale)
        XCTAssertNil(environment["LC_ALL"])
    }

    func testPTYEnvironmentPreservesInheritedUTF8Locale() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "LANG": "fr_CA.UTF-8",
            "LC_CTYPE": "en_US.UTF-8",
            "LC_ALL": "en_GB.UTF-8",
        ])

        XCTAssertEqual(environment["LANG"], "fr_CA.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "en_GB.UTF-8")
    }

    func testPTYEnvironmentAppliesTerminalStateOverrides() {
        let environment = PTYProcess.terminalEnvironment(
            from: ["PATH": "/usr/bin:/bin"],
            overrides: [
                "GHOSTNOTCH_AGENT_STATE_FILE": "/tmp/ghostnotch-agent-state",
                "GHOSTNOTCH_AGENT_EVENT_LOG": "/tmp/ghostnotch-agent-events.jsonl",
            ]
        )

        XCTAssertEqual(environment["GHOSTNOTCH_AGENT_STATE_FILE"], "/tmp/ghostnotch-agent-state")
        XCTAssertEqual(environment["GHOSTNOTCH_AGENT_EVENT_LOG"], "/tmp/ghostnotch-agent-events.jsonl")
    }

    func testSessionRunsCommandAndCapturesOutput() async throws {
        let state = TerminalSessionState(outputLimit: 16 * 1024)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            state: state
        )

        try session.start(cols: 80, rows: 24)
        defer {
            session.stop()
        }

        let marker = "GHOSTNOTCH_TEST_\(UUID().uuidString)"
        try session.write("printf '\\n\(marker)\\n'\n")

        try await waitForOutput(containing: marker, in: state)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(state.phase, .running)
    }

    func testSessionStartsInStartingPhaseUntilFirstOutput() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)

        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.phase, .starting)

        process.emitOutput("$ ")

        XCTAssertEqual(state.phase, .running)
        XCTAssertNil(state.lastError)
        XCTAssertTrue(state.hasReceivedOutput)
        XCTAssertTrue(state.outputText.isEmpty)
    }

    func testSessionStateCapturesOutputOnlyWhenExplicitlyRequested() {
        let lifecycleOnly = TerminalSessionState()
        lifecycleOnly.appendOutput(Data("prompt".utf8))

        XCTAssertTrue(lifecycleOnly.hasReceivedOutput)
        XCTAssertTrue(lifecycleOnly.outputText.isEmpty)

        let captured = TerminalSessionState(outputLimit: 16)
        captured.appendOutput(Data("prompt".utf8))

        XCTAssertTrue(captured.hasReceivedOutput)
        XCTAssertEqual(captured.outputText, "prompt")
    }

    func testStartupTimeoutRecordsVisibleErrorAndStopsProcess() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/zsh"]),
            state: state,
            process: process,
            startupTimeout: 0.05
        )

        try session.start(cols: 80, rows: 24)
        try await waitForPhase(.failed, in: state)

        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(process.stopCallCount, 1)
        XCTAssertTrue(state.lastError?.contains("Terminal startup timed out") == true)
        XCTAssertTrue(state.lastError?.contains("/bin/zsh") == true)
    }

    func testOutputCancelsStartupTimeout() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process,
            startupTimeout: 0.05
        )

        try session.start(cols: 80, rows: 24)
        process.emitOutput("$ ")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(state.phase, .running)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(process.stopCallCount, 0)
    }

    func testAgentActivityStateParsesRawFileValues() {
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: "idle\n"), .idle)
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: " working "), .working)
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: "ATTENTION"), .attention)
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: "busy"), .idle)
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: ""), .idle)
    }

    func testAgentActivityStateParsesStructuredJSONEnvelopeValues() {
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"codex","state":"idle","event":"SessionStart"}"#
            ),
            .idle
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"codex","state":"working","event":"UserPromptSubmit"}"#
            ),
            .working
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"codex","state":"attention","event":"PermissionRequest"}"#
            ),
            .attention
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"claude","state":"working","event":"UserPromptSubmit"}"#
            ),
            .working
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"Claude","state":"ATTENTION","event":"Elicitation"}"#
            ),
            .attention
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"pi","state":"working","event":"UserPromptSubmit"}"#
            ),
            .idle
        )
        XCTAssertEqual(
            TerminalAgentActivityState(
                rawFileValue: #"{"version":1,"agent":"codex","state":"busy","event":"UserPromptSubmit"}"#
            ),
            .idle
        )
        XCTAssertEqual(TerminalAgentActivityState(rawFileValue: #"{"agent":"codex","state":"working""#), .idle)
    }

    func testAgentActivityRecordParsesStructuredMetadataAndLegacyValues() {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let codexRecord = TerminalAgentActivityRecord(
            rawFileValue: agentActivityEnvelope(
                agent: "codex",
                state: "working",
                event: "PreToolUse",
                timestamp: timestamp
            )
        )

        XCTAssertEqual(codexRecord.agent, .codex)
        XCTAssertEqual(codexRecord.state, .working)
        XCTAssertEqual(codexRecord.event, "PreToolUse")
        XCTAssertEqual(codexRecord.timestamp?.timeIntervalSince1970 ?? 0, timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertFalse(codexRecord.isLegacy)

        let legacyRecord = TerminalAgentActivityRecord(rawFileValue: "working\n")
        XCTAssertEqual(legacyRecord.agent, .unknown)
        XCTAssertEqual(legacyRecord.state, .working)
        XCTAssertNil(legacyRecord.event)
        XCTAssertNil(legacyRecord.timestamp)
        XCTAssertTrue(legacyRecord.isLegacy)

        let malformedRecord = TerminalAgentActivityRecord(rawFileValue: #"{"agent":"codex","state":"working""#)
        XCTAssertEqual(malformedRecord.agent, .unknown)
        XCTAssertEqual(malformedRecord.state, .idle)
        XCTAssertFalse(malformedRecord.isLegacy)
    }

    func testAgentActivityStatePublishesWorkingToIdleTransition() {
        let state = TerminalSessionState()
        var publishedStates: [TerminalAgentActivityState] = []

        let cancellable = state.$agentActivityState
            .dropFirst()
            .sink { publishedStates.append($0) }

        state.updateAgentActivityState(.working)
        state.updateAgentActivityState(.idle)

        XCTAssertEqual(publishedStates, [.working, .idle])
        withExtendedLifetime(cancellable) {}
    }

    func testPTYOutputDoesNotMarkAgentAsWorking() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        process.emitOutput("$ ")

        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testAgentStateFileDrivesWorkingAndAttentionStates() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        guard let stateFilePath = process.startEnvironmentOverrides.last?["GHOSTNOTCH_AGENT_STATE_FILE"] else {
            return XCTFail("Expected GhostNotch agent state file override")
        }
        XCTAssertNotNil(process.startEnvironmentOverrides.last?["GHOSTNOTCH_AGENT_EVENT_LOG"])

        try "working\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)

        try "idle\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.idle, in: state)

        try "working\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)

        try "attention\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.attention, in: state)

        try "invalid\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.idle, in: state)
    }

    func testAgentStateFileDrivesStructuredJSONAttentionWorkingIdleTransitions() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        guard let stateFilePath = process.startEnvironmentOverrides.last?["GHOSTNOTCH_AGENT_STATE_FILE"] else {
            return XCTFail("Expected GhostNotch agent state file override")
        }

        try #"{"version":1,"agent":"codex","state":"attention","event":"PermissionRequest"}"#
            .write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.attention, in: state)

        try #"{"version":1,"agent":"claude","state":"working","event":"ElicitationResult"}"#
            .write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)

        try #"{"version":1,"agent":"claude","state":"idle","event":"Stop"}"#
            .write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.idle, in: state)
    }

    func testCodexWorkingStateExpiresToIdleWithoutRewritingStateFile() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process,
            codexWorkingFreshnessTimeout: 0.2
        )

        try session.start(cols: 80, rows: 24)
        guard let stateFilePath = process.startEnvironmentOverrides.last?["GHOSTNOTCH_AGENT_STATE_FILE"] else {
            return XCTFail("Expected GhostNotch agent state file override")
        }

        try agentActivityEnvelope(
            agent: "codex",
            state: "working",
            event: "PreToolUse",
            timestamp: Date()
        ).write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)

        let expiredEnvelope = agentActivityEnvelope(
            agent: "codex",
            state: "working",
            event: "PreToolUse",
            timestamp: Date().addingTimeInterval(-5)
        )
        try expiredEnvelope.write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.idle, in: state)
        XCTAssertEqual(try String(contentsOfFile: stateFilePath, encoding: .utf8), expiredEnvelope)
    }

    func testCodexAttentionClaudeWorkingAndLegacyWorkingDoNotExpire() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process,
            codexWorkingFreshnessTimeout: 0.1
        )

        try session.start(cols: 80, rows: 24)
        guard let stateFilePath = process.startEnvironmentOverrides.last?["GHOSTNOTCH_AGENT_STATE_FILE"] else {
            return XCTFail("Expected GhostNotch agent state file override")
        }

        try agentActivityEnvelope(
            agent: "codex",
            state: "attention",
            event: "PermissionRequest",
            timestamp: Date().addingTimeInterval(-5)
        ).write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.attention, in: state)

        try agentActivityEnvelope(
            agent: "claude",
            state: "working",
            event: "ElicitationResult",
            timestamp: Date().addingTimeInterval(-5)
        ).write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(state.agentActivityState, .working)

        try "working\n".write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        try await waitForAgentActivityState(.working, in: state)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(state.agentActivityState, .working)
    }

    func testAgentActivityClearsWhenSessionStopsOrFails() {
        let state = TerminalSessionState()

        state.markRunning()
        state.updateAgentActivityState(.working)
        XCTAssertEqual(state.agentActivityState, .working)

        state.markStopped()
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateAgentActivityState(.attention)
        XCTAssertEqual(state.agentActivityState, .attention)

        state.recordError("boom")
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testRestartClearsOutputAndStartsFreshShell() async throws {
        let state = TerminalSessionState(outputLimit: 16 * 1024)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            state: state
        )

        try session.start(cols: 80, rows: 24)
        defer {
            session.stop()
        }

        let firstMarker = "GHOSTNOTCH_BEFORE_RESTART_\(UUID().uuidString)"
        try session.write("printf '\\n\(firstMarker)\\n'\n")
        try await waitForOutput(containing: firstMarker, in: state)

        try session.restart(cols: 72, rows: 20)

        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.phase, .starting)
        XCTAssertFalse(state.outputText.contains(firstMarker))

        let secondMarker = "GHOSTNOTCH_AFTER_RESTART_\(UUID().uuidString)"
        try session.write("printf '\\n\(secondMarker)\\n'\n")
        try await waitForOutput(containing: secondMarker, in: state)

        XCTAssertFalse(state.outputText.contains(firstMarker))
        XCTAssertEqual(state.phase, .running)
    }

    func testRestartDoesNotWaitForTerminationCallback() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.notifyOnStop = false
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        try session.restart(cols: 72, rows: 20)

        XCTAssertEqual(process.startCallCount, 2)
        XCTAssertEqual(process.stopCallCount, 1)
        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.phase, .starting)
    }

    func testRestartIgnoresStaleTerminationCallback() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.notifyOnStop = false
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        try session.restart(cols: 72, rows: 20)
        process.emitTermination(markProcessStopped: false)

        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.phase, .starting)
    }

    func testCoordinatorCoalescesOutputBeforeRendering() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = SpyRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        try session.start(cols: 80, rows: 24)
        process.emitOutput("a")
        process.emitOutput("b")
        coordinator.flushPendingOutputForTesting()

        XCTAssertEqual(engine.processedOutput, [Data("ab".utf8)])
        XCTAssertTrue(state.hasReceivedOutput)
        XCTAssertTrue(state.outputText.isEmpty)
    }

    func testCoordinatorRestartPreservesMeasuredGridResize() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = SpyRenderingEngine()
        let measuredResize = TerminalGridResize(columns: 100, rows: 28, cellWidthPixels: 9, cellHeightPixels: 18)
        engine.lastAppliedGridResize = measuredResize
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        coordinator.restartPreservingGrid(currentSnapshot: .empty(columns: 40, rows: 10))

        XCTAssertEqual(engine.resetRequests, [TerminalGridSize(columns: 100, rows: 28)])
        XCTAssertEqual(process.startRequests.last, TerminalGridSize(columns: 100, rows: 28))
    }

    func testCoordinatorPublishesWorkingDirectoryFromSnapshot() {
        let state = TerminalSessionState()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: FakeTerminalProcess()
        )
        let engine = SpyRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        engine.publish(snapshot: .empty(columns: 80, rows: 24, currentWorkingDirectory: "/tmp/project"))

        XCTAssertEqual(coordinator.state.currentWorkingDirectory, "/tmp/project")
    }

    func testStoppingSessionMarksItStopped() throws {
        let state = TerminalSessionState(outputLimit: 16 * 1024)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            state: state
        )

        try session.start(cols: 80, rows: 24)
        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)

        session.stop()

        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.phase, .stopped)
    }

    func testTerminalPasteMappingSanitizesUnsafeEscapesWithoutBracketedWrappers() {
        XCTAssertEqual(TerminalInputMapping.data(forPastedText: "echo hi\u{1B}\n"), Data("echo hi \r".utf8))
        XCTAssertNil(TerminalInputMapping.data(forPastedText: ""))
    }

    func testTerminalPasteMappingUsesBracketedWrappersOnlyWhenRequested() {
        XCTAssertEqual(
            TerminalInputMapping.data(forPastedText: "echo hi\u{1B}\n", bracketed: true),
            Data("\u{1B}[200~echo hi \n\u{1B}[201~".utf8)
        )
        XCTAssertEqual(
            TerminalInputMapping.data(forPastedText: "echo hi\u{1B}\n", bracketed: false),
            Data("echo hi \r".utf8)
        )
    }

    private func waitForOutput(containing text: String, in state: TerminalSessionState) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if state.outputText.contains(text) {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Terminal session did not capture command output. Output was: \(state.outputText)")
    }

    private func waitForPhase(_ phase: TerminalSessionPhase, in state: TerminalSessionState) async throws {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if state.phase == phase {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Terminal session did not reach phase \(phase). Current phase: \(state.phase)")
    }

    private func waitForAgentActivityState(
        _ expectedValue: TerminalAgentActivityState,
        in state: TerminalSessionState
    ) async throws {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if state.agentActivityState == expectedValue {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Agent activity state did not become \(expectedValue). Current value: \(state.agentActivityState)")
    }

    private func agentActivityEnvelope(
        agent: String,
        state: String,
        event: String,
        timestamp: Date
    ) -> String {
        """
        {"agent":"\(agent)","event":"\(event)","state":"\(state)","timestamp":"\(isoTimestamp(timestamp))","version":1}
        """
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

@MainActor
private final class FakeTerminalProcess: @MainActor TerminalProcess {
    var onOutput: TerminalOutputHandler?
    var onTermination: TerminalTerminationHandler?
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var startRequests: [TerminalGridSize] = []
    private(set) var startEnvironmentOverrides: [[String: String]] = []
    var notifyOnStop = false

    func start(
        shell: String,
        workingDirectory: String,
        cols: Int,
        rows: Int,
        environmentOverrides: [String: String]
    ) throws {
        startCallCount += 1
        startRequests.append(TerminalGridSize(columns: cols, rows: rows))
        startEnvironmentOverrides.append(environmentOverrides)
        isRunning = true
    }

    func stop() -> Bool {
        stopCallCount += 1
        let wasRunning = isRunning
        isRunning = false

        if notifyOnStop {
            onTermination?()
        }

        return wasRunning
    }

    func write(_ data: Data) throws {}

    func resize(cols: Int, rows: Int) throws {}

    func emitOutput(_ text: String) {
        onOutput?(Data(text.utf8))
    }

    func emitTermination(markProcessStopped: Bool = true) {
        if markProcessStopped {
            isRunning = false
        }
        onTermination?()
    }
}

private struct TerminalGridSize: Equatable {
    let columns: Int
    let rows: Int
}

@MainActor
private final class SpyRenderingEngine: TerminalRenderingEngine {
    var snapshot = TerminalRenderSnapshot.empty()
    var lastAppliedGridResize: TerminalGridResize?
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?
    private(set) var processedOutput: [Data] = []
    private(set) var resetRequests: [TerminalGridSize] = []

    func start(session: TerminalSession) {}

    func processOutput(_ data: Data) {
        processedOutput.append(data)
        onSnapshotChange?(snapshot)
    }

    func sendInput(_ input: Data) {}

    func sendKeyEvent(_ event: TerminalKeyEvent) {}

    func handleScrollWheel(_ event: TerminalScrollEvent) {}

    func handleMouseEvent(_ event: TerminalMouseEvent) {}

    func resize(cols: Int, rows: Int, cellWidthPixels: Int, cellHeightPixels: Int) {
        lastAppliedGridResize = TerminalGridResize(
            columns: cols,
            rows: rows,
            cellWidthPixels: cellWidthPixels,
            cellHeightPixels: cellHeightPixels
        )
    }

    func reset(cols: Int, rows: Int) {
        resetRequests.append(TerminalGridSize(columns: cols, rows: rows))
    }

    func publish(snapshot: TerminalRenderSnapshot) {
        self.snapshot = snapshot
        onSnapshotChange?(snapshot)
    }

    func focus() {}

    func blur() {}
}
