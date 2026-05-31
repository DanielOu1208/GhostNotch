import Combine
import Foundation

enum TerminalSessionPhase: Equatable {
    case stopped
    case starting
    case running
    case failed
}

@MainActor
final class TerminalSessionState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase: TerminalSessionPhase = .stopped
    @Published private(set) var hasReceivedOutput = false
    @Published private(set) var lastError: String?
    @Published private(set) var currentWorkingDirectory: String?

    private var capturedOutput = Data()
    private let outputCaptureLimit: Int?

    init(outputLimit: Int? = nil) {
        outputCaptureLimit = outputLimit
    }

    var outputText: String {
        String(decoding: capturedOutput, as: UTF8.self)
    }

    func markStarting() {
        isRunning = true
        phase = .starting
        lastError = nil
    }

    func markRunning() {
        isRunning = true
        phase = .running
        lastError = nil
    }

    func markStopped() {
        isRunning = false
        phase = .stopped
    }

    func recordError(_ error: Error) {
        recordError(error.localizedDescription)
    }

    func recordError(_ message: String) {
        lastError = message
        isRunning = false
        phase = .failed
    }

    func appendOutput(_ data: Data) {
        hasReceivedOutput = true

        guard let outputCaptureLimit else {
            return
        }

        capturedOutput.append(data)

        if capturedOutput.count > outputCaptureLimit {
            capturedOutput.removeFirst(capturedOutput.count - outputCaptureLimit)
        }
    }

    func clearOutput() {
        hasReceivedOutput = false
        capturedOutput.removeAll(keepingCapacity: true)
    }

    func updateWorkingDirectory(_ path: String?) {
        guard currentWorkingDirectory != path else {
            return
        }

        currentWorkingDirectory = path
    }
}
