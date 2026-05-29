import XCTest

@MainActor
final class TerminalSessionTests: XCTestCase {
    func testPTYEnvironmentForcesConservativeTermType() {
        let environment = PTYProcess.terminalEnvironment(from: [
            "SHELL": "/bin/sh",
            "TERM": "xterm-ghostty",
            "PATH": "/usr/bin:/bin",
        ])

        XCTAssertEqual(environment["TERM"], PTYProcess.defaultTerminalType)
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
}

@MainActor
private final class FakeTerminalProcess: @MainActor TerminalProcess {
    var onOutput: TerminalOutputHandler?
    var onTermination: TerminalTerminationHandler?
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var startRequests: [TerminalGridSize] = []
    var notifyOnStop = false

    func start(shell: String, workingDirectory: String, cols: Int, rows: Int) throws {
        startCallCount += 1
        startRequests.append(TerminalGridSize(columns: cols, rows: rows))
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

    func focus() {}

    func blur() {}
}
