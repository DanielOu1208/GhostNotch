import XCTest

@MainActor
final class TerminalSurfaceCoordinatorTests: XCTestCase {
    func testCoordinatorLaunchesAgentAfterFreshShellReportsRunning() async throws {
        let state = TerminalSessionState()
        let process = CoordinatorTestTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = CoordinatorTestRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        let launchTask = Task {
            await coordinator.launchAgent(
                .codex,
                currentSnapshot: .empty(columns: 80, rows: 24),
                startupTimeout: 1
            )
        }

        try await waitForStartCallCount(1, in: process)
        XCTAssertEqual(engine.sentInputs, [])

        process.emitOutput("$ ")
        await launchTask.value

        XCTAssertEqual(process.startCallCount, 1)
        XCTAssertEqual(process.stopCallCount, 0)
        XCTAssertEqual(process.startWorkingDirectories, [FileManager.default.homeDirectoryForCurrentUser.path])
        XCTAssertEqual(engine.sentInputs, [Data("codex\n".utf8)])
    }

    func testCoordinatorRestartsRunningShellBeforeLaunchingAgent() async throws {
        let state = TerminalSessionState()
        let process = CoordinatorTestTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = CoordinatorTestRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        try session.start(cols: 80, rows: 24)
        process.emitOutput("$ ")
        XCTAssertEqual(state.phase, .running)

        let launchTask = Task {
            await coordinator.launchAgent(
                .claude,
                currentSnapshot: .empty(columns: 100, rows: 28),
                directoryPath: "/tmp/project",
                startupTimeout: 1
            )
        }

        try await waitForStartCallCount(2, in: process)
        XCTAssertEqual(process.stopCallCount, 1)
        XCTAssertEqual(engine.sentInputs, [])

        process.emitOutput("$ ")
        await launchTask.value

        XCTAssertEqual(engine.resetRequests, [CoordinatorTestTerminalGridSize(columns: 100, rows: 28)])
        XCTAssertEqual(
            process.startWorkingDirectories,
            [FileManager.default.homeDirectoryForCurrentUser.path, "/tmp/project"]
        )
        XCTAssertEqual(engine.sentInputs, [Data("claude\n".utf8)])
    }

    func testCanceledAgentLaunchDoesNotWriteCommandAfterShellBecomesReady() async throws {
        let state = TerminalSessionState()
        let process = CoordinatorTestTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = CoordinatorTestRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        let launchTask = Task {
            await coordinator.launchAgent(
                .codex,
                currentSnapshot: .empty(columns: 80, rows: 24),
                startupTimeout: 1
            )
        }

        try await waitForStartCallCount(1, in: process)
        launchTask.cancel()
        process.emitOutput("$ ")
        await launchTask.value

        XCTAssertEqual(engine.sentInputs, [])
    }

    func testCoordinatorResetsStoppedSessionWithPreviousOutputBeforeLaunchingAgent() async throws {
        let state = TerminalSessionState()
        let process = CoordinatorTestTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = CoordinatorTestRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        try session.start(cols: 80, rows: 24)
        process.emitOutput("old shell output")
        session.stop()

        let launchTask = Task {
            await coordinator.launchAgent(
                .codex,
                currentSnapshot: .empty(columns: 90, rows: 22),
                startupTimeout: 1
            )
        }

        try await waitForStartCallCount(2, in: process)
        process.emitOutput("$ ")
        await launchTask.value

        XCTAssertEqual(engine.resetRequests, [CoordinatorTestTerminalGridSize(columns: 90, rows: 22)])
        XCTAssertEqual(engine.sentInputs, [Data("codex\n".utf8)])
    }

    func testCoordinatorLaunchesAgentInSelectedDirectory() async throws {
        let state = TerminalSessionState()
        let process = CoordinatorTestTerminalProcess()
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            state: state,
            process: process
        )
        let engine = CoordinatorTestRenderingEngine()
        let coordinator = TerminalSurfaceCoordinator(session: session, engine: engine)

        let launchTask = Task {
            await coordinator.launchAgent(
                .codex,
                currentSnapshot: .empty(columns: 80, rows: 24),
                directoryPath: "/Users/danielou/My Project",
                startupTimeout: 1
            )
        }

        try await waitForStartCallCount(1, in: process)
        process.emitOutput("$ ")
        await launchTask.value

        XCTAssertEqual(process.startWorkingDirectories, ["/Users/danielou/My Project"])
        XCTAssertEqual(engine.sentInputs, [Data("codex\n".utf8)])
    }

    private func waitForStartCallCount(
        _ expectedValue: Int,
        in process: CoordinatorTestTerminalProcess
    ) async throws {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if process.startCallCount == expectedValue {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Terminal process start count did not become \(expectedValue). Current value: \(process.startCallCount)")
    }
}

@MainActor
private final class CoordinatorTestTerminalProcess: @MainActor TerminalProcess {
    var onOutput: TerminalOutputHandler?
    var onTermination: TerminalTerminationHandler?
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var startWorkingDirectories: [String] = []

    func start(
        shell: String,
        workingDirectory: String,
        cols: Int,
        rows: Int,
        environmentOverrides: [String: String]
    ) throws {
        startCallCount += 1
        startWorkingDirectories.append(workingDirectory)
        isRunning = true
    }

    func stop() -> Bool {
        stopCallCount += 1
        let wasRunning = isRunning
        isRunning = false
        return wasRunning
    }

    func write(_ data: Data) throws {}

    func resize(cols: Int, rows: Int) throws {}

    func emitOutput(_ text: String) {
        onOutput?(Data(text.utf8))
    }
}

private struct CoordinatorTestTerminalGridSize: Equatable {
    let columns: Int
    let rows: Int
}

@MainActor
private final class CoordinatorTestRenderingEngine: TerminalRenderingEngine {
    var snapshot = TerminalRenderSnapshot.empty()
    var lastAppliedGridResize: TerminalGridResize?
    var onSnapshotChange: ((TerminalRenderSnapshot) -> Void)?
    private(set) var resetRequests: [CoordinatorTestTerminalGridSize] = []
    private(set) var sentInputs: [Data] = []

    func start(session: TerminalSession) {}

    func processOutput(_ data: Data) {}

    func sendInput(_ input: Data) {
        sentInputs.append(input)
    }

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
        resetRequests.append(CoordinatorTestTerminalGridSize(columns: cols, rows: rows))
    }

    func focus() {}

    func blur() {}
}
