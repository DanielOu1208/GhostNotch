import Darwin
import Foundation

enum PTYProcessError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case notRunning
    case ptyOpenFailed(errno: Int32)
    case descriptorDuplicationFailed(errno: Int32)
    case processLaunchFailed(String)
    case writeFailed(errno: Int32)
    case resizeFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Terminal process is already running."
        case .notRunning:
            "Terminal process is not running."
        case .ptyOpenFailed(let errno):
            "Failed to open pseudo-terminal: \(String(cString: strerror(errno)))."
        case .descriptorDuplicationFailed(let errno):
            "Failed to prepare terminal file descriptors: \(String(cString: strerror(errno)))."
        case .processLaunchFailed(let message):
            "Failed to launch shell process: \(message)."
        case .writeFailed(let errno):
            "Failed to write to terminal: \(String(cString: strerror(errno)))."
        case .resizeFailed(let errno):
            "Failed to resize terminal: \(String(cString: strerror(errno)))."
        }
    }
}

final class PTYProcess: TerminalProcess, @unchecked Sendable {
    static let defaultTerminalType = "xterm-256color"
    static let termProgram = "GhostNotch"
    static let termProgramVersion = "dev"
    static let defaultColorTerminal = "truecolor"
    static let shellIntegrationResourceSubdirectory = "ShellIntegration"
    static let defaultUTF8Locale = "en_US.UTF-8"
    private static let inheritedHerdrConfigurationVariables: Set<String> = [
        "HERDR_CONFIG_PATH",
        "HERDR_DISABLE_SOUND",
        "HERDR_LOG",
        "HERDR_SESSION",
    ]
    fileprivate static let defaultExecutableSearchPath = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    var onOutput: TerminalOutputHandler?
    var onTermination: TerminalTerminationHandler?

    private let readQueue = DispatchQueue(label: "com.ghostnotch.terminal.pty.read")
    private let terminationQueue = DispatchQueue(label: "com.ghostnotch.terminal.pty.terminate")
    private let processInspectionQueue = DispatchQueue(label: "com.ghostnotch.terminal.pty.process-inspection")
    private let lock = NSLock()
    private var masterFileDescriptor: Int32 = -1
    private var process: Process?
    private var readSource: DispatchSourceRead?
    private var generation = 0

    var isRunning: Bool {
        lock.withLock {
            process?.isRunning ?? false
        }
    }

    func descendantProcessSnapshot(matching executableNames: Set<String>) async -> TerminalProcessSnapshot {
        await withCheckedContinuation { continuation in
            processInspectionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: TerminalProcessSnapshot(descendants: [], foregroundProcessGroupID: nil))
                    return
                }
                continuation.resume(returning: self.makeDescendantProcessSnapshot(matching: executableNames))
            }
        }
    }

    private func makeDescendantProcessSnapshot(matching executableNames: Set<String>) -> TerminalProcessSnapshot {
        let processState = lock.withLock {
            (process?.processIdentifier, masterFileDescriptor)
        }
        guard let rootProcessID = processState.0 else {
            return TerminalProcessSnapshot(descendants: [], foregroundProcessGroupID: nil)
        }

        let normalizedExecutableNames = Set(executableNames.map { $0.lowercased() })
        var pendingProcessIDs = Self.childProcessIDs(of: rootProcessID).map { ($0, 1) }
        var visitedProcessIDs = Set<pid_t>()
        var matches: [TerminalDescendantProcess] = []

        while let (processID, depth) = pendingProcessIDs.popLast() {
            guard visitedProcessIDs.insert(processID).inserted else { continue }

            let names = Self.processCommandNames(processID).intersection(normalizedExecutableNames)
            if !names.isEmpty {
                matches.append(
                    TerminalDescendantProcess(
                        processID: processID,
                        processGroupID: Self.processGroupID(processID),
                        depth: depth,
                        commandNames: names
                    )
                )
            }
            pendingProcessIDs.append(contentsOf: Self.childProcessIDs(of: processID).map { ($0, depth + 1) })
        }

        let foregroundGroup = processState.1 >= 0 ? tcgetpgrp(processState.1) : -1
        return TerminalProcessSnapshot(
            descendants: matches,
            foregroundProcessGroupID: foregroundGroup > 0 ? foregroundGroup : nil
        )
    }

    func start(
        shell: String,
        workingDirectory: String,
        cols: Int = 80,
        rows: Int = 24,
        environmentOverrides: [String: String] = [:]
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else {
            throw PTYProcessError.alreadyRunning
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw PTYProcessError.ptyOpenFailed(errno: errno)
        }

        let shellProcess: Process
        do {
            shellProcess = try makeProcess(
                shell: shell,
                workingDirectory: workingDirectory,
                slave: slave,
                environmentOverrides: environmentOverrides
            )
            generation += 1
            let processGeneration = generation
            shellProcess.terminationHandler = { [weak self] _ in
                self?.handleProcessTermination(generation: processGeneration)
            }
            try shellProcess.run()
        } catch {
            close(master)
            close(slave)
            throw error
        }

        close(slave)
        masterFileDescriptor = master
        process = shellProcess
        startReading(from: master, generation: generation)
    }

    func write(_ data: Data) throws {
        let descriptor = try currentMasterFileDescriptor()

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten
                )

                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw PTYProcessError.writeFailed(errno: errno)
                }

                bytesWritten += result
            }
        }
    }

    func resize(cols: Int, rows: Int) throws {
        let descriptor = try currentMasterFileDescriptor()
        var windowSize = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard ioctl(descriptor, TIOCSWINSZ, &windowSize) == 0 else {
            throw PTYProcessError.resizeFailed(errno: errno)
        }

        if let processID = lock.withLock({ process?.processIdentifier }) {
            kill(processID, SIGWINCH)
        }
    }

    @discardableResult
    func stop() -> Bool {
        let shellProcess: Process?
        let descriptor: Int32
        let source: DispatchSourceRead?

        lock.lock()
        shellProcess = process
        descriptor = masterFileDescriptor
        source = readSource
        process = nil
        masterFileDescriptor = -1
        readSource = nil
        generation += 1
        lock.unlock()

        source?.cancel()

        if descriptor >= 0 {
            close(descriptor)
        }

        guard let shellProcess else {
            return false
        }

        let request = ProcessTerminationRequest(process: shellProcess)
        terminationQueue.async {
            Self.terminate(request.process)
        }
        return true
    }

    deinit {
        stop()
    }

    private func currentMasterFileDescriptor() throws -> Int32 {
        let descriptor = lock.withLock { masterFileDescriptor }
        guard descriptor >= 0 else {
            throw PTYProcessError.notRunning
        }

        return descriptor
    }

    private static func childProcessIDs(of processID: pid_t) -> [pid_t] {
        var capacity = 16

        while capacity <= 4096 {
            var childProcessIDs = [pid_t](repeating: 0, count: capacity)
            let count = proc_listchildpids(
                processID,
                &childProcessIDs,
                Int32(childProcessIDs.count * MemoryLayout<pid_t>.stride)
            )
            guard count > 0 else {
                return []
            }
            if count < capacity {
                return Array(childProcessIDs.prefix(Int(count)))
            }
            capacity *= 2
        }

        return []
    }

    private static func processCommandNames(_ processID: pid_t) -> Set<String> {
        var names = Set<String>()
        var nameBuffer = [CChar](repeating: 0, count: 256)
        if proc_name(processID, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            names.insert(string(from: nameBuffer).lowercased())
        }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(processID, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            names.insert(
                URL(fileURLWithPath: string(from: pathBuffer)).lastPathComponent.lowercased()
            )
        }

        for argument in processArguments(processID, limit: 2) {
            names.insert(URL(fileURLWithPath: argument).lastPathComponent.lowercased())
        }

        return names
    }

    private static func processGroupID(_ processID: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, pointer, Int32(size))
        }
        return result == size ? pid_t(info.pbi_pgid) : nil
    }

    private static func string(from buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private static func processArguments(_ processID: pid_t, limit: Int) -> [String] {
        var managementInformationBase = [CTL_KERN, KERN_PROCARGS2, processID]
        var bufferSize = 0
        guard sysctl(&managementInformationBase, 3, nil, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.size
        else {
            return []
        }

        var buffer = [UInt8](repeating: 0, count: bufferSize)
        guard sysctl(&managementInformationBase, 3, &buffer, &bufferSize, nil, 0) == 0 else {
            return []
        }

        let argumentCount = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        guard argumentCount > 0 else {
            return []
        }

        var index = MemoryLayout<Int32>.size
        while index < bufferSize, buffer[index] != 0 {
            index += 1
        }
        while index < bufferSize, buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        while arguments.count < min(argumentCount, limit), index < bufferSize {
            let argumentStart = index
            while index < bufferSize, buffer[index] != 0 {
                index += 1
            }
            if argumentStart < index {
                arguments.append(String(decoding: buffer[argumentStart..<index], as: UTF8.self))
            }
            while index < bufferSize, buffer[index] == 0 {
                index += 1
            }
        }
        return arguments
    }

    private func startReading(from descriptor: Int32, generation: Int) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailableOutput(generation: generation)
        }
        source.resume()

        readSource = source
    }

    private func readAvailableOutput(generation eventGeneration: Int) {
        let descriptor = lock.withLock {
            guard eventGeneration == generation else {
                return Int32(-1)
            }

            return masterFileDescriptor
        }
        guard descriptor >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(descriptor, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(buffer.prefix(bytesRead))
            if let onOutput {
                Task { @MainActor in
                    onOutput(data)
                }
            }
            return
        }

        if bytesRead == 0 || errno != EINTR {
            handleProcessTermination(generation: eventGeneration)
        }
    }

    private func notifyTermination() {
        guard let onTermination else {
            return
        }

        Task { @MainActor in
            onTermination()
        }
    }

    private func handleProcessTermination(generation eventGeneration: Int) {
        let descriptor: Int32
        let source: DispatchSourceRead?

        lock.lock()
        guard eventGeneration == generation else {
            lock.unlock()
            return
        }

        guard process != nil || masterFileDescriptor >= 0 || readSource != nil else {
            lock.unlock()
            return
        }

        descriptor = masterFileDescriptor
        source = readSource
        process = nil
        masterFileDescriptor = -1
        readSource = nil
        generation += 1
        lock.unlock()

        source?.cancel()

        if descriptor >= 0 {
            close(descriptor)
        }

        notifyTermination()
    }

    private func makeProcess(
        shell: String,
        workingDirectory: String,
        slave: Int32,
        environmentOverrides: [String: String]
    ) throws -> Process {
        let standardInputDescriptor = dup(slave)
        let standardOutputDescriptor = dup(slave)
        let standardErrorDescriptor = dup(slave)

        guard standardInputDescriptor >= 0,
              standardOutputDescriptor >= 0,
              standardErrorDescriptor >= 0 else {
            let capturedErrno = errno
            closeIfValid(standardInputDescriptor)
            closeIfValid(standardOutputDescriptor)
            closeIfValid(standardErrorDescriptor)
            throw PTYProcessError.descriptorDuplicationFailed(errno: capturedErrno)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.environment = Self.terminalEnvironment(
            from: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides
        )
        process.standardInput = FileHandle(fileDescriptor: standardInputDescriptor, closeOnDealloc: true)
        process.standardOutput = FileHandle(fileDescriptor: standardOutputDescriptor, closeOnDealloc: true)
        process.standardError = FileHandle(fileDescriptor: standardErrorDescriptor, closeOnDealloc: true)

        do {
            _ = try process.executableURL?.checkResourceIsReachable()
        } catch {
            throw PTYProcessError.processLaunchFailed(error.localizedDescription)
        }

        return process
    }

    static func terminalEnvironment(
        from environment: [String: String],
        overrides: [String: String] = [:]
    ) -> [String: String] {
        var terminalEnvironment = environment
        terminalEnvironment.removeValue(forKey: "NO_COLOR")
        let inheritedHerdrContext = terminalEnvironment.keys.filter {
            $0.hasPrefix("HERDR_") && !inheritedHerdrConfigurationVariables.contains($0)
        }
        for key in inheritedHerdrContext {
            terminalEnvironment.removeValue(forKey: key)
        }
        terminalEnvironment["TERM"] = defaultTerminalType
        terminalEnvironment["TERM_PROGRAM"] = termProgram
        terminalEnvironment["TERM_PROGRAM_VERSION"] = termProgramVersion
        terminalEnvironment["GHOSTNOTCH_VERSION"] = termProgramVersion
        terminalEnvironment["COLORTERM"] = defaultColorTerminal
        terminalEnvironment["GHOSTNOTCH_RESOURCES_DIR"] = shellIntegrationResourceDirectory()
        for (key, value) in overrides {
            terminalEnvironment[key] = value
        }
        terminalEnvironment.applyDefaultUTF8Locale()
        terminalEnvironment.applyDefaultExecutableSearchPath()
        return terminalEnvironment
    }

    private static func shellIntegrationResourceDirectory() -> String {
        let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return resourceURL.appendingPathComponent(shellIntegrationResourceSubdirectory, isDirectory: true).path
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()

        for _ in 0..<50 {
            if !process.isRunning {
                return
            }
            usleep(10_000)
        }

        kill(process.processIdentifier, SIGKILL)

        for _ in 0..<50 {
            if !process.isRunning {
                return
            }
            usleep(10_000)
        }

        NSLog("GhostNotch terminal child process did not exit promptly after SIGKILL: \(process.processIdentifier)")
    }
}

private struct ProcessTerminationRequest: @unchecked Sendable {
    let process: Process
}

private extension Dictionary where Key == String, Value == String {
    mutating func applyDefaultExecutableSearchPath() {
        let inheritedPaths = self["PATH"]?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        let inheritedUniquePaths = inheritedPaths.uniqued()

        guard !inheritedUniquePaths.isEmpty else {
            self["PATH"] = PTYProcess.defaultExecutableSearchPath.joined(separator: ":")
            return
        }

        let inheritedPathSet = Set(inheritedUniquePaths)
        let missingDefaultPaths = PTYProcess.defaultExecutableSearchPath.filter { !inheritedPathSet.contains($0) }
        self["PATH"] = (missingDefaultPaths + inheritedUniquePaths).joined(separator: ":")
    }

    mutating func applyDefaultUTF8Locale() {
        if shouldUseDefaultUTF8Locale(for: self["LANG"]) {
            self["LANG"] = PTYProcess.defaultUTF8Locale
        }

        if shouldUseDefaultUTF8Locale(for: self["LC_CTYPE"]) {
            self["LC_CTYPE"] = PTYProcess.defaultUTF8Locale
        }

        if shouldUseDefaultUTF8Locale(for: self["LC_ALL"]) {
            removeValue(forKey: "LC_ALL")
        }
    }

    private func shouldUseDefaultUTF8Locale(for value: String?) -> Bool {
        guard let value else {
            return true
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "c" || normalized == "posix"
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private func closeIfValid(_ descriptor: Int32) {
    if descriptor >= 0 {
        close(descriptor)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
