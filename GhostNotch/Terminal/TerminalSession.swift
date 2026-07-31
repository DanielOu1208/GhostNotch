import Foundation

typealias TerminalOutputHandler = @MainActor @Sendable (Data) -> Void
typealias TerminalTerminationHandler = @MainActor @Sendable () -> Void

struct TerminalDescendantProcess: Equatable, Sendable {
    let processID: Int32
    let processGroupID: Int32?
    let depth: Int
    let commandNames: Set<String>
}

struct TerminalProcessSnapshot: Equatable, Sendable {
    let descendants: [TerminalDescendantProcess]
    let foregroundProcessGroupID: Int32?
}

protocol TerminalProcess: AnyObject, Sendable {
    var onOutput: TerminalOutputHandler? { get set }
    var onTermination: TerminalTerminationHandler? { get set }
    var isRunning: Bool { get }

    func descendantProcessSnapshot(matching executableNames: Set<String>) async -> TerminalProcessSnapshot

    func start(
        shell: String,
        workingDirectory: String,
        cols: Int,
        rows: Int,
        environmentOverrides: [String: String]
    ) throws
    func stop() -> Bool
    func write(_ data: Data) throws
    func resize(cols: Int, rows: Int) throws
}

enum TerminalSessionError: LocalizedError, Equatable {
    case startupTimeout(shell: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .startupTimeout(let shell, let seconds):
            let timeout = seconds.formatted(.number.precision(.fractionLength(0...1)))
            return "Terminal startup timed out after \(timeout) seconds while launching \(shell). Your shell startup files may be blocking. Restart the terminal or check your shell profile scripts."
        }
    }
}

@MainActor
final class TerminalSession {
    let state: TerminalSessionState

    static let defaultStartupTimeout: TimeInterval = 5

    private let shellResolver: ShellResolver
    private let defaultWorkingDirectory: String
    private let startupTimeout: TimeInterval
    private let process: any TerminalProcess
    private var outputObservers: [@MainActor (Data) -> Void] = []
    private var lifecycleGeneration = 0
    private var startupWatchdogTask: Task<Void, Never>?
    private var agentStatusMonitorTask: Task<Void, Never>?

    init(
        shellResolver: ShellResolver = ShellResolver(),
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        state: TerminalSessionState? = nil,
        process: any TerminalProcess = PTYProcess(),
        startupTimeout: TimeInterval = TerminalSession.defaultStartupTimeout
    ) {
        self.shellResolver = shellResolver
        defaultWorkingDirectory = workingDirectory
        self.state = state ?? TerminalSessionState()
        self.process = process
        self.startupTimeout = startupTimeout
        process.onOutput = { [weak self] data in
            self?.state.appendOutput(data)
            if self?.state.phase == .starting {
                self?.state.markRunning()
                self?.cancelStartupWatchdog()
            }
            self?.notifyOutputObservers(data)
        }

        process.onTermination = { [weak self] in
            self?.handleProcessTermination()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    func start(cols: Int = 80, rows: Int = 24, workingDirectory: String? = nil) throws {
        lifecycleGeneration += 1
        try launch(
            cols: cols,
            rows: rows,
            workingDirectory: workingDirectory,
            generation: lifecycleGeneration
        )
    }

    func stop() {
        cancelStartupWatchdog()
        stopAgentStatusMonitoring()
        lifecycleGeneration += 1
        state.markStopped()
        _ = process.stop()
    }

    func restart(cols: Int = 80, rows: Int = 24, workingDirectory: String? = nil) throws {
        cancelStartupWatchdog()
        stopAgentStatusMonitoring()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        state.clearOutput()
        state.markStopped()
        _ = process.stop()

        try launch(
            cols: cols,
            rows: rows,
            workingDirectory: workingDirectory,
            generation: generation
        )
    }

    func write(_ data: Data) throws {
        do {
            try process.write(data)
        } catch {
            state.recordError(error)
            throw error
        }
    }

    func write(_ text: String) throws {
        guard let data = text.data(using: .utf8) else {
            return
        }

        try write(data)
    }

    func resize(cols: Int, rows: Int) throws {
        do {
            try process.resize(cols: cols, rows: rows)
        } catch {
            state.recordError(error)
            throw error
        }
    }

    func addOutputObserver(_ observer: @escaping @MainActor (Data) -> Void) {
        outputObservers.append(observer)
    }

    private func notifyOutputObservers(_ data: Data) {
        for observer in outputObservers {
            observer(data)
        }
    }

    private func handleProcessTermination() {
        guard !process.isRunning, state.phase != .failed, state.phase != .stopped else {
            return
        }

        cancelStartupWatchdog()
        stopAgentStatusMonitoring()
        state.markStopped()
    }

    private func launch(cols: Int, rows: Int, workingDirectory: String?, generation: Int) throws {
        let shell = shellResolver.resolve()

        do {
            try process.start(
                shell: shell,
                workingDirectory: workingDirectory ?? defaultWorkingDirectory,
                cols: cols,
                rows: rows,
                environmentOverrides: [:]
            )
            state.markStarting()
            startAgentStatusMonitoring(generation: generation)
            scheduleStartupWatchdog(shell: shell, generation: generation)
        } catch {
            cancelStartupWatchdog()
            stopAgentStatusMonitoring()
            state.recordError(error)
            throw error
        }
    }

    private func scheduleStartupWatchdog(shell: String, generation: Int) {
        cancelStartupWatchdog()

        startupWatchdogTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, self?.startupTimeout ?? 0) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await MainActor.run {
                self?.handleStartupTimeout(shell: shell, generation: generation)
            }
        }
    }

    private func handleStartupTimeout(shell: String, generation: Int) {
        guard generation == lifecycleGeneration,
              state.phase == .starting,
              process.isRunning
        else {
            return
        }

        stopAgentStatusMonitoring()
        _ = process.stop()
        state.recordError(TerminalSessionError.startupTimeout(shell: shell, seconds: startupTimeout))
    }

    private func cancelStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }

    private func startAgentStatusMonitoring(generation: Int) {
        stopAgentStatusMonitoring()

        agentStatusMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAgentActivityState(generation: generation)

                do {
                    let fastRefresh = await MainActor.run {
                        self?.state.agentStatusNeedsFastRefresh == true
                    }
                    try await Task.sleep(nanoseconds: fastRefresh ? 100_000_000 : 300_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func stopAgentStatusMonitoring() {
        agentStatusMonitorTask?.cancel()
        agentStatusMonitorTask = nil
    }

    private func refreshAgentActivityState(generation: Int) async {
        guard generation == lifecycleGeneration, process.isRunning else {
            state.updateDetectedAgentProcess(nil)
            return
        }

        let snapshot = await process.descendantProcessSnapshot(
            matching: Set(AgentLauncher.all.map { $0.command.lowercased() })
        )
        guard generation == lifecycleGeneration, process.isRunning else {
            return
        }

        state.updateDetectedAgentProcess(
            Self.selectAgentProcess(from: snapshot, previous: state.activeAgentProcessIdentity)
        )
        state.refreshAgentStatus()
    }

    private static func selectAgentProcess(
        from snapshot: TerminalProcessSnapshot,
        previous: TerminalAgentProcessIdentity?
    ) -> TerminalAgentProcessIdentity? {
        let candidates = snapshot.descendants.compactMap { process -> (TerminalAgentProcessIdentity, Int, Int32?)? in
            guard let launcher = AgentLauncher.all.first(where: { launcher in
                process.commandNames.contains(launcher.command.lowercased())
            }) else {
                return nil
            }
            return (
                TerminalAgentProcessIdentity(agent: launcher.id, processID: process.processID),
                process.depth,
                process.processGroupID
            )
        }

        let foreground = snapshot.foregroundProcessGroupID.flatMap { foregroundGroup in
            let matches = candidates.filter { $0.2 == foregroundGroup }
            return matches.isEmpty ? nil : matches
        }
        let eligible = foreground ?? candidates
        guard let deepest = eligible.map(\.1).max() else { return nil }
        let deepestCandidates = eligible.filter { $0.1 == deepest }.map(\.0)

        if let previous, deepestCandidates.contains(previous) {
            return previous
        }
        return deepestCandidates.count == 1 ? deepestCandidates[0] : nil
    }
}
