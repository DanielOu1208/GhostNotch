import Combine
import Foundation

enum TerminalSessionPhase: Equatable {
    case stopped
    case starting
    case running
    case failed
}

enum TerminalAgentActivityState: String, Equatable {
    case idle
    case working
    case attention

    init(rawFileValue: String) {
        self = TerminalAgentActivityRecord(rawFileValue: rawFileValue).state
    }
}

enum TerminalAgentActivityAgent: String, Equatable {
    case codex
    case claude
    case unknown
}

struct TerminalAgentActivityRecord: Equatable {
    private static let supportedAgents = Set(["codex", "claude"])

    let agent: TerminalAgentActivityAgent
    let state: TerminalAgentActivityState
    let event: String?
    let timestamp: Date?
    let isLegacy: Bool

    init(
        agent: TerminalAgentActivityAgent,
        state: TerminalAgentActivityState,
        event: String? = nil,
        timestamp: Date? = nil,
        isLegacy: Bool
    ) {
        self.agent = agent
        self.state = state
        self.event = event
        self.timestamp = timestamp
        self.isLegacy = isLegacy
    }

    init(rawFileValue: String) {
        let trimmedValue = rawFileValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let structuredRecord = Self.structuredRecord(from: trimmedValue) {
            self = structuredRecord
            return
        }

        self = TerminalAgentActivityRecord(
            agent: .unknown,
            state: TerminalAgentActivityState(rawValue: trimmedValue.lowercased()) ?? .idle,
            isLegacy: true
        )
    }

    private static func structuredRecord(from rawValue: String) -> TerminalAgentActivityRecord? {
        guard rawValue.first == "{",
              let data = rawValue.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(AgentActivityEnvelope.self, from: data)
        else {
            return rawValue.first == "{" ? malformedStructuredRecord : nil
        }

        let normalizedAgent = envelope.agent.lowercased()
        guard supportedAgents.contains(normalizedAgent),
              let agent = TerminalAgentActivityAgent(rawValue: normalizedAgent),
              let state = TerminalAgentActivityState(rawValue: envelope.state.lowercased())
        else {
            return malformedStructuredRecord
        }

        return TerminalAgentActivityRecord(
            agent: agent,
            state: state,
            event: envelope.event,
            timestamp: parseTimestamp(envelope.timestamp),
            isLegacy: false
        )
    }

    private static var malformedStructuredRecord: TerminalAgentActivityRecord {
        TerminalAgentActivityRecord(agent: .unknown, state: .idle, isLegacy: false)
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct AgentActivityEnvelope: Decodable {
    let agent: String
    let state: String
    let event: String?
    let timestamp: String?
}

@MainActor
final class TerminalSessionState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase: TerminalSessionPhase = .stopped
    @Published private(set) var hasReceivedOutput = false
    @Published private(set) var agentActivityState: TerminalAgentActivityState = .idle
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
        updateAgentActivityState(.idle)
    }

    func recordError(_ error: Error) {
        recordError(error.localizedDescription)
    }

    func recordError(_ message: String) {
        lastError = message
        isRunning = false
        phase = .failed
        updateAgentActivityState(.idle)
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
        updateAgentActivityState(.idle)
    }

    func updateWorkingDirectory(_ path: String?) {
        guard currentWorkingDirectory != path else {
            return
        }

        currentWorkingDirectory = path
    }

    func updateAgentActivityState(_ newState: TerminalAgentActivityState) {
        guard agentActivityState != newState else {
            return
        }

        agentActivityState = newState
    }
}
