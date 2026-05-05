import Foundation

struct ShellResolver {
    static let defaultFallbackShell = "/bin/zsh"

    private let environment: [String: String]
    private let fileManager: FileManager
    private let fallbackShell: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        fallbackShell: String = ShellResolver.defaultFallbackShell
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.fallbackShell = fallbackShell
    }

    func resolve() -> String {
        guard let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !shell.isEmpty,
              isExecutableFile(atPath: shell)
        else {
            return fallbackShell
        }

        return shell
    }

    private func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return fileManager.isExecutableFile(atPath: path)
    }
}
