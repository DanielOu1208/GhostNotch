import Foundation

typealias TerminalOutputHandler = @MainActor @Sendable (Data) -> Void
typealias TerminalTerminationHandler = @MainActor @Sendable () -> Void

protocol TerminalProcess: AnyObject {
    var onOutput: TerminalOutputHandler? { get set }
    var onTermination: TerminalTerminationHandler? { get set }
    var isRunning: Bool { get }

    func start(shell: String, workingDirectory: String, cols: Int, rows: Int) throws
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
    private let workingDirectory: String
    private let startupTimeout: TimeInterval
    private let process: any TerminalProcess
    private var outputObservers: [@MainActor (Data) -> Void] = []
    private var lifecycleGeneration = 0
    private var startupWatchdogTask: Task<Void, Never>?

    init(
        shellResolver: ShellResolver = ShellResolver(),
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        state: TerminalSessionState? = nil,
        process: any TerminalProcess = PTYProcess(),
        startupTimeout: TimeInterval = TerminalSession.defaultStartupTimeout
    ) {
        self.shellResolver = shellResolver
        self.workingDirectory = workingDirectory
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

    func start(cols: Int = 80, rows: Int = 24) throws {
        lifecycleGeneration += 1
        try launch(cols: cols, rows: rows, generation: lifecycleGeneration)
    }

    func stop() {
        cancelStartupWatchdog()
        lifecycleGeneration += 1
        _ = process.stop()
        state.markStopped()
    }

    func restart(cols: Int = 80, rows: Int = 24) throws {
        cancelStartupWatchdog()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        state.clearOutput()
        _ = process.stop()

        try launch(cols: cols, rows: rows, generation: generation)
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
        guard !process.isRunning, state.phase != .failed else {
            return
        }

        cancelStartupWatchdog()
        state.markStopped()
    }

    private func launch(cols: Int, rows: Int, generation: Int) throws {
        let shell = shellResolver.resolve()

        do {
            try process.start(
                shell: shell,
                workingDirectory: workingDirectory,
                cols: cols,
                rows: rows
            )
            state.markStarting()
            scheduleStartupWatchdog(shell: shell, generation: generation)
        } catch {
            cancelStartupWatchdog()
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

        _ = process.stop()
        state.recordError(TerminalSessionError.startupTimeout(shell: shell, seconds: startupTimeout))
    }

    private func cancelStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }
}

enum TerminalInputMapping {
    static let returnData = Data([0x0D])
    static let tabData = Data([0x09])
    static let deleteData = Data([0x7F])

    static func data(forInsertedText text: String) -> Data? {
        guard !text.isEmpty else {
            return nil
        }

        return text
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
            .data(using: .utf8)
    }

    static func data(forPastedText text: String, bracketed: Bool = false) -> Data? {
        GhosttyTerminalCore.encodePaste(text, bracketed: bracketed)
    }

    static func data(forKeyCode keyCode: UInt16, characters: String?) -> Data? {
        switch keyCode {
        case 36, 76:
            return returnData
        case 48:
            return tabData
        case 51, 117:
            return deleteData
        default:
            guard let characters, !characters.isEmpty else {
                return nil
            }

            return data(forInsertedText: characters)
        }
    }
}
