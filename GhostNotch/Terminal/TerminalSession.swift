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
