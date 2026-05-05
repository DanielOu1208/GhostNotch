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

final class PTYProcess: @unchecked Sendable {
    typealias OutputHandler = @MainActor @Sendable (Data) -> Void
    typealias TerminationHandler = @MainActor @Sendable () -> Void

    var onOutput: OutputHandler?
    var onTermination: TerminationHandler?

    private let readQueue = DispatchQueue(label: "com.ghostnotch.terminal.pty.read")
    private let lock = NSLock()
    private var masterFileDescriptor: Int32 = -1
    private var process: Process?
    private var readSource: DispatchSourceRead?

    var isRunning: Bool {
        lock.withLock {
            process?.isRunning ?? false
        }
    }

    func start(shell: String, workingDirectory: String, cols: Int = 80, rows: Int = 24) throws {
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
            shellProcess = try makeProcess(shell: shell, workingDirectory: workingDirectory, slave: slave)
            shellProcess.terminationHandler = { [weak self] _ in
                self?.handleProcessTermination()
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
        startReading(from: master)
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

    func stop() {
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
        lock.unlock()

        source?.cancel()

        if descriptor >= 0 {
            close(descriptor)
        }

        guard let shellProcess else {
            return
        }

        terminate(shellProcess)
        notifyTermination()
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

    private func startReading(from descriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailableOutput()
        }
        source.resume()

        readSource = source
    }

    private func readAvailableOutput() {
        let descriptor = lock.withLock { masterFileDescriptor }
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
            handleProcessTermination()
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

    private func handleProcessTermination() {
        let descriptor: Int32
        let source: DispatchSourceRead?

        lock.lock()
        guard process != nil || masterFileDescriptor >= 0 || readSource != nil else {
            lock.unlock()
            return
        }

        descriptor = masterFileDescriptor
        source = readSource
        process = nil
        masterFileDescriptor = -1
        readSource = nil
        lock.unlock()

        source?.cancel()

        if descriptor >= 0 {
            close(descriptor)
        }

        notifyTermination()
    }

    private func makeProcess(shell: String, workingDirectory: String, slave: Int32) throws -> Process {
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
        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "xterm-256color"]) { current, _ in
            current
        }
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

    private func terminate(_ process: Process) {
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
        process.waitUntilExit()
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
