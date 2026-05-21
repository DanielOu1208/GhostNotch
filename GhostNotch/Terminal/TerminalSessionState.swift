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
    @Published private(set) var outputData = Data()
    @Published private(set) var lastError: String?

    private let outputLimit: Int

    init(outputLimit: Int = 128 * 1024) {
        self.outputLimit = outputLimit
    }

    var outputText: String {
        String(decoding: outputData, as: UTF8.self)
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
        outputData.append(data)

        if outputData.count > outputLimit {
            outputData.removeFirst(outputData.count - outputLimit)
        }
    }

    func clearOutput() {
        outputData.removeAll(keepingCapacity: true)
    }
}
