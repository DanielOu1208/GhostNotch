import Foundation

@MainActor
final class TerminalSession {
    let state: TerminalSessionState

    private let shellResolver: ShellResolver
    private let workingDirectory: String
    private let process: PTYProcess

    init(
        shellResolver: ShellResolver = ShellResolver(),
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        state: TerminalSessionState? = nil,
        process: PTYProcess = PTYProcess()
    ) {
        self.shellResolver = shellResolver
        self.workingDirectory = workingDirectory
        self.state = state ?? TerminalSessionState()
        self.process = process

        process.onOutput = { [weak self] data in
            self?.state.appendOutput(data)
        }

        process.onTermination = { [weak self] in
            self?.state.markStopped()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    func start(cols: Int = 80, rows: Int = 24) throws {
        do {
            try process.start(
                shell: shellResolver.resolve(),
                workingDirectory: workingDirectory,
                cols: cols,
                rows: rows
            )
            state.markRunning()
        } catch {
            state.recordError(error)
            throw error
        }
    }

    func stop() {
        process.stop()
        state.markStopped()
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
}
