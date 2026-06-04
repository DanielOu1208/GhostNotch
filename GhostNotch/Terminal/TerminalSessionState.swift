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

enum CodexTerminalQuestionSelectorDetector {
    static func isQuestionSelectorVisible(in snapshot: TerminalRenderSnapshot) -> Bool {
        isQuestionSelectorVisible(in: snapshot.plainText)
    }

    static func isQuestionSelectorVisible(in text: String) -> Bool {
        let normalizedText = text.lowercased()
        guard normalizedText.contains("unanswered"),
              normalizedText.contains("enter to submit answer"),
              normalizedText.contains("esc to interrupt"),
              hasQuestionMarker(in: text)
        else {
            return false
        }

        return hasNumberedChoices(in: text)
    }

    private static func hasQuestionMarker(in text: String) -> Bool {
        text.range(
            of: #"Question\s+\d+\s*/\s*\d+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func hasNumberedChoices(in text: String) -> Bool {
        let matches = text.matches(of: #"(?m)^\s*(?:>\s*)?\d+\.\s+\S"#)
        return matches.count >= 2
    }
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
    private var hookActivityRecord = TerminalAgentActivityRecord(agent: .unknown, state: .idle, isLegacy: true)
    private var hasCodexVisibleQuestionSelector = false

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
        resetAgentActivityState()
    }

    func recordError(_ error: Error) {
        recordError(error.localizedDescription)
    }

    func recordError(_ message: String) {
        lastError = message
        isRunning = false
        phase = .failed
        resetAgentActivityState()
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
        resetAgentActivityState()
    }

    func updateWorkingDirectory(_ path: String?) {
        guard currentWorkingDirectory != path else {
            return
        }

        currentWorkingDirectory = path
    }

    func updateAgentActivityState(_ newState: TerminalAgentActivityState) {
        hookActivityRecord = TerminalAgentActivityRecord(agent: .unknown, state: newState, isLegacy: true)
        clearCodexQuestionSelectorOverride()
        resolveAgentActivityState()
    }

    func updateAgentActivityRecord(_ record: TerminalAgentActivityRecord) {
        let isNewRecord = record != hookActivityRecord
        hookActivityRecord = record

        if isNewRecord,
           (record.agent != .codex || record.state != .working || record.isLegacy) {
            setCodexVisibleQuestionSelector(false)
        }

        resolveAgentActivityState()
    }

    func updateVisibleTerminalSnapshot(_ snapshot: TerminalRenderSnapshot) {
        let visibleText = snapshot.plainText
        guard hookActivityRecord.agent == .codex,
              hookActivityRecord.state == .working,
              hookActivityRecord.isLegacy == false
        else {
            setCodexVisibleQuestionSelector(false)
            return
        }

        let isVisibleQuestionSelector = CodexTerminalQuestionSelectorDetector.isQuestionSelectorVisible(in: visibleText)
        setCodexVisibleQuestionSelector(isVisibleQuestionSelector)
    }

    private func resetAgentActivityState() {
        hookActivityRecord = TerminalAgentActivityRecord(agent: .unknown, state: .idle, isLegacy: true)
        clearCodexQuestionSelectorOverride()
        resolveAgentActivityState()
    }

    private func setCodexVisibleQuestionSelector(_ isVisible: Bool) {
        guard hasCodexVisibleQuestionSelector != isVisible else { return }

        hasCodexVisibleQuestionSelector = isVisible
        resolveAgentActivityState()
    }

    private func clearCodexQuestionSelectorOverride() {
        hasCodexVisibleQuestionSelector = false
    }

    private func resolveAgentActivityState() {
        let resolvedState: TerminalAgentActivityState
        if hookActivityRecord.agent == .codex,
           hookActivityRecord.state == .working,
           hookActivityRecord.isLegacy == false,
           hasCodexVisibleQuestionSelector {
            resolvedState = .idle
        } else {
            resolvedState = hookActivityRecord.state
        }

        guard agentActivityState != resolvedState else {
            return
        }

        agentActivityState = resolvedState
    }
}

private extension String {
    func matches(of pattern: String) -> [String] {
        guard let regularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regularExpression.matches(in: self, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: self) else {
                return nil
            }

            return String(self[matchRange])
        }
    }
}
