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

    func testPTYEnvironmentRemovesHostContextAndAppliesExplicitOverrides() {
        let environment = PTYProcess.terminalEnvironment(
            from: [
                "PATH": "/usr/bin:/bin",
                "NO_COLOR": "1",
                "HERDR_ENV": "1",
                "HERDR_PANE_ID": "outer-pane",
                "HERDR_SOCKET_PATH": "/tmp/outer.sock",
                "HERDR_CONFIG_PATH": "/tmp/herdr.toml",
                "HERDR_SESSION": "work",
                "SSH_AUTH_SOCK": "/tmp/agent.sock",
                "CUSTOM_VALUE": "preserved",
            ],
            overrides: [
                "GHOSTNOTCH_TEST_OVERRIDE": "enabled",
                "HERDR_ENV": "intentional",
            ]
        )

        XCTAssertNil(environment["NO_COLOR"])
        XCTAssertNil(environment["HERDR_PANE_ID"])
        XCTAssertNil(environment["HERDR_SOCKET_PATH"])
        XCTAssertEqual(environment["HERDR_CONFIG_PATH"], "/tmp/herdr.toml")
        XCTAssertEqual(environment["HERDR_SESSION"], "work")
        XCTAssertEqual(environment["SSH_AUTH_SOCK"], "/tmp/agent.sock")
        XCTAssertEqual(environment["CUSTOM_VALUE"], "preserved")
        XCTAssertEqual(environment["HERDR_ENV"], "intentional")
        XCTAssertEqual(environment["GHOSTNOTCH_TEST_OVERRIDE"], "enabled")
    }

    func testPTYProcessFindsSymlinkedDescendantByInvokedAgentName() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostnotch-process-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let agentURL = temporaryDirectory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(
            at: agentURL,
            withDestinationURL: URL(fileURLWithPath: "/bin/sleep")
        )

        let process = PTYProcess()
        try process.start(
            shell: "/bin/sh",
            workingDirectory: temporaryDirectory.path,
            cols: 80,
            rows: 24,
            environmentOverrides: [:]
        )
        defer {
            _ = process.stop()
        }

        try process.write(Data("./codex 2\n".utf8))
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let snapshot = await process.descendantProcessSnapshot(matching: ["codex"])
            if snapshot.descendants.contains(where: { $0.commandNames.contains("codex") }) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Expected the symlinked Codex process in the PTY descendant tree")
    }

    func testPTYProcessFindsScriptAgentByScriptArgument() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostnotch-script-process-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let agentURL = temporaryDirectory.appendingPathComponent("opencode")
        try "#!/bin/sh\n/bin/sleep 2\n".write(to: agentURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: agentURL.path
        )

        let process = PTYProcess()
        try process.start(
            shell: "/bin/sh",
            workingDirectory: temporaryDirectory.path,
            cols: 80,
            rows: 24,
            environmentOverrides: [:]
        )
        defer {
            _ = process.stop()
        }

        try process.write(Data("./opencode\n".utf8))
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let snapshot = await process.descendantProcessSnapshot(matching: ["opencode"])
            if snapshot.descendants.contains(where: { $0.commandNames.contains("opencode") }) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Expected the script-backed OpenCode process in the PTY descendant tree")
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

    func testHasReceivedOutputPublishesOnlyWhenItsValueChanges() {
        let state = TerminalSessionState()
        var publishedValues: [Bool] = []
        let cancellable = state.$hasReceivedOutput.sink { publishedValues.append($0) }

        state.appendOutput(Data("first".utf8))
        state.appendOutput(Data("second".utf8))
        state.clearOutput()
        state.clearOutput()
        state.appendOutput(Data("third".utf8))

        XCTAssertEqual(publishedValues, [false, true, false, true])
        withExtendedLifetime(cancellable) {}
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

        let processSnapshotCallCount = process.snapshotCallCount
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(process.snapshotCallCount, processSnapshotCallCount)
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

    func testSessionDoesNotInjectAgentHookEnvironment() throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)

        XCTAssertEqual(process.startEnvironmentOverrides, [[:]])
    }

    func testKnownAgentClearsWhenItsProcessExits() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.snapshot = .agent(.codex, processID: 42)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        try await waitForActiveAgent(.codex, in: state)

        process.snapshot = TerminalProcessSnapshot(descendants: [], foregroundProcessGroupID: nil)

        try await waitForActiveAgent(nil, in: state)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testProcessIdentityAppearsWithoutHooks() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.snapshot = .agent(.claude, processID: 84)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)

        try await waitForActiveAgent(.claude, in: state)
        XCTAssertEqual(state.activeAgentProcessIdentity?.processID, 84)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testForegroundProcessGroupWinsOverDeeperBackgroundAgent() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.snapshot = TerminalProcessSnapshot(
            descendants: [
                TerminalDescendantProcess(
                    processID: 10,
                    processGroupID: 10,
                    depth: 1,
                    commandNames: ["codex"]
                ),
                TerminalDescendantProcess(
                    processID: 20,
                    processGroupID: 20,
                    depth: 3,
                    commandNames: ["claude"]
                ),
            ],
            foregroundProcessGroupID: 10
        )
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        try await waitForActiveAgent(.codex, in: state)
        XCTAssertEqual(state.activeAgentProcessIdentity?.processID, 10)
    }

    func testAmbiguousDeepestAgentsDoNotClaimTheIndicator() async throws {
        let state = TerminalSessionState()
        let process = FakeTerminalProcess()
        process.snapshot = TerminalProcessSnapshot(
            descendants: [
                TerminalDescendantProcess(
                    processID: 10,
                    processGroupID: 10,
                    depth: 2,
                    commandNames: ["codex"]
                ),
                TerminalDescendantProcess(
                    processID: 20,
                    processGroupID: 20,
                    depth: 2,
                    commandNames: ["claude"]
                ),
            ],
            foregroundProcessGroupID: nil
        )
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )

        try session.start(cols: 80, rows: 24)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(state.activeAgent)
        XCTAssertEqual(state.agentActivityState, .idle)
    }

    func testAgentActivityClearsWhenSessionStopsOrFails() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        let codex = TerminalAgentProcessIdentity(agent: .codex, processID: 7)

        state.markRunning()
        state.updateDetectedAgentProcess(codex)
        state.updateAgentStatusEvidence(TerminalAgentStatusEvidence())
        state.updateAgentStatusEvidence(statusEvidence(title: "⠋ Working", titleSequence: 1))
        XCTAssertEqual(state.agentActivityState, .working)

        state.markStopped()
        XCTAssertEqual(state.agentActivityState, .idle)

        state.markRunning()
        state.updateDetectedAgentProcess(codex)
        state.updateAgentStatusEvidence(statusEvidence(title: "Action Required", titleSequence: 2))
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

    func testCoordinatorRoutesAgentEvidenceSeparatelyFromRenderSnapshots() {
        let state = TerminalSessionState(agentStartupGrace: 0)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: FakeTerminalProcess()
        )
        let engine = SpyRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)
        state.updateDetectedAgentProcess(TerminalAgentProcessIdentity(agent: .codex, processID: 7))

        engine.publish(evidence: statusEvidence(title: "⠋ Working", titleSequence: 1))

        XCTAssertEqual(coordinator.state.agentActivityState, .working)
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

    private func waitForActiveAgent(
        _ expectedValue: TerminalAgentActivityAgent?,
        in state: TerminalSessionState
    ) async throws {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if state.activeAgent == expectedValue {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Active agent did not become \(String(describing: expectedValue)). Current value: \(String(describing: state.activeAgent))")
    }

    private func statusEvidence(title: String?, titleSequence: UInt64) -> TerminalAgentStatusEvidence {
        TerminalAgentStatusEvidence(
            text: "",
            textSequence: 0,
            title: title,
            titleSequence: titleSequence,
            progress: nil,
            progressSequence: 0
        )
    }
}

private final class FakeTerminalProcess: TerminalProcess, @unchecked Sendable {
    var onOutput: TerminalOutputHandler?
    var onTermination: TerminalTerminationHandler?
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var startRequests: [TerminalGridSize] = []
    private(set) var startEnvironmentOverrides: [[String: String]] = []
    private(set) var snapshotCallCount = 0
    var notifyOnStop = false
    var snapshot = TerminalProcessSnapshot(descendants: [], foregroundProcessGroupID: nil)

    func descendantProcessSnapshot(matching executableNames: Set<String>) async -> TerminalProcessSnapshot {
        snapshotCallCount += 1
        return TerminalProcessSnapshot(
            descendants: snapshot.descendants.compactMap { process in
                let names = process.commandNames.intersection(executableNames)
                guard !names.isEmpty else { return nil }
                return TerminalDescendantProcess(
                    processID: process.processID,
                    processGroupID: process.processGroupID,
                    depth: process.depth,
                    commandNames: names
                )
            },
            foregroundProcessGroupID: snapshot.foregroundProcessGroupID
        )
    }

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
            MainActor.assumeIsolated {
                onTermination?()
            }
        }

        return wasRunning
    }

    func write(_ data: Data) throws {}

    func resize(cols: Int, rows: Int) throws {}

    @MainActor
    func emitOutput(_ text: String) {
        onOutput?(Data(text.utf8))
    }

    @MainActor
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

private extension TerminalProcessSnapshot {
    static func agent(
        _ agent: TerminalAgentActivityAgent,
        processID: Int32,
        processGroupID: Int32? = nil,
        depth: Int = 1
    ) -> TerminalProcessSnapshot {
        TerminalProcessSnapshot(
            descendants: [
                TerminalDescendantProcess(
                    processID: processID,
                    processGroupID: processGroupID,
                    depth: depth,
                    commandNames: [AgentLauncher.launcher(for: agent)?.command ?? agent.rawValue]
                ),
            ],
            foregroundProcessGroupID: processGroupID
        )
    }
}

@MainActor
private final class SpyRenderingEngine: TerminalRenderingEngine {
    var snapshot = TerminalRenderSnapshot.empty()
    var lastAppliedGridResize: TerminalGridResize?
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?
    var onAgentStatusEvidenceChange: ((TerminalAgentStatusEvidence) -> Void)?
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

    func publish(evidence: TerminalAgentStatusEvidence) {
        onAgentStatusEvidenceChange?(evidence)
    }

    func focus() {}

    func blur() {}
}
