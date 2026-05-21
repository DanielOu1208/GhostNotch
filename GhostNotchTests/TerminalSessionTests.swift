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
        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
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

    func testTerminalInputMappingPreservesTextAndNormalizesNewlines() {
        XCTAssertEqual(TerminalInputMapping.data(forInsertedText: "pwd"), Data("pwd".utf8))
        XCTAssertEqual(TerminalInputMapping.data(forInsertedText: "echo hi\n"), Data("echo hi\r".utf8))
        XCTAssertNil(TerminalInputMapping.data(forInsertedText: ""))
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
    var notifyOnStop = false

    func start(shell: String, workingDirectory: String, cols: Int, rows: Int) throws {
        startCallCount += 1
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
