import Combine
import Foundation

@MainActor
final class TerminalSessionState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var outputData = Data()
    @Published private(set) var lastError: String?

    private let outputLimit: Int

    init(outputLimit: Int = 128 * 1024) {
        self.outputLimit = outputLimit
    }

    var outputText: String {
        String(decoding: outputData, as: UTF8.self)
    }

    func markRunning() {
        isRunning = true
        lastError = nil
    }

    func markStopped() {
        isRunning = false
    }

    func recordError(_ error: Error) {
        lastError = error.localizedDescription
        isRunning = false
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
