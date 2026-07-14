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

struct AgentStatusIndicatorStyle: Equatable {
    enum ColorRole: Equatable {
        case ready
        case working
        case waiting
    }

    let colorRole: ColorRole
    let animates: Bool
    let label: String

    static func style(
        for state: TerminalAgentActivityState,
        reducesMotion: Bool
    ) -> AgentStatusIndicatorStyle {
        switch state {
        case .idle:
            AgentStatusIndicatorStyle(colorRole: .ready, animates: false, label: "Ready")
        case .working:
            AgentStatusIndicatorStyle(
                colorRole: .working,
                animates: !reducesMotion,
                label: "Working"
            )
        case .attention:
            AgentStatusIndicatorStyle(
                colorRole: .waiting,
                animates: !reducesMotion,
                label: "Waiting"
            )
        }
    }
}

enum TerminalAgentActivityAgent: String, Equatable {
    case codex
    case claude
    case unknown

    static let supportedCases: [TerminalAgentActivityAgent] = [.codex, .claude]

    var executableName: String? {
        switch self {
        case .codex:
            "codex"
        case .claude:
            "claude"
        case .unknown:
            nil
        }
    }
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

enum CodexTerminalUserSelectorDetector {
    static func isUserSelectorVisible(in snapshot: TerminalRenderSnapshot) -> Bool {
        isUserSelectorVisible(in: snapshot.plainText)
    }

    static func isUserSelectorVisible(in text: String) -> Bool {
        isQuestionSelectorVisible(in: text) || isPlanImplementationSelectorVisible(in: text)
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

    static func isPlanImplementationSelectorVisible(in text: String) -> Bool {
        let normalizedText = text.lowercased()
        guard normalizedText.contains("implement this plan?"),
              normalizedText.contains("yes, implement this plan"),
              normalizedText.contains("yes, clear context and implement"),
              normalizedText.contains("no, stay in plan mode"),
              normalizedText.contains("press enter to confirm or esc to go back")
        else {
            return false
        }

        return hasPlanImplementationChoices(in: text)
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

    private static func hasPlanImplementationChoices(in text: String) -> Bool {
        let choicePatterns = [
            #"(?m)^\s*(?:>\s*)?1\.\s+Yes,\s+implement\s+this\s+plan\b"#,
            #"(?m)^\s*(?:>\s*)?2\.\s+Yes,\s+clear\s+context\s+and\s+implement\b"#,
            #"(?m)^\s*(?:>\s*)?3\.\s+No,\s+stay\s+in\s+Plan\s+mode\b"#
        ]

        return choicePatterns.allSatisfy { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

@MainActor
final class TerminalSessionState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase: TerminalSessionPhase = .stopped
    @Published private(set) var hasReceivedOutput = false
    @Published private(set) var agentActivityState: TerminalAgentActivityState = .idle
    @Published private(set) var activeAgent: TerminalAgentActivityAgent?
    @Published private(set) var lastError: String?
    @Published private(set) var currentWorkingDirectory: String?

    private var capturedOutput = Data()
    private let outputCaptureLimit: Int?
    private let codexSelectorDwellNanoseconds: UInt64
    private var hookActivityRecord = TerminalAgentActivityRecord(agent: .unknown, state: .idle, isLegacy: true)
    private var hasConfirmedCodexVisibleUserSelector = false
    private var pendingCodexUserSelectorTask: Task<Void, Never>?
    private var codexUserSelectorGeneration = 0

    init(
        outputLimit: Int? = nil,
        codexSelectorDwellNanoseconds: UInt64 = 200_000_000
    ) {
        outputCaptureLimit = outputLimit
        self.codexSelectorDwellNanoseconds = codexSelectorDwellNanoseconds
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
        if !hasReceivedOutput {
            hasReceivedOutput = true
        }

        guard let outputCaptureLimit else {
            return
        }

        capturedOutput.append(data)

        if capturedOutput.count > outputCaptureLimit {
            capturedOutput.removeFirst(capturedOutput.count - outputCaptureLimit)
        }
    }

    func clearOutput() {
        if hasReceivedOutput {
            hasReceivedOutput = false
        }
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
        clearCodexUserSelectorOverride()
        resolveAgentActivityState()
    }

    func updateAgentActivityRecord(_ record: TerminalAgentActivityRecord) {
        let isNewRecord = record != hookActivityRecord
        hookActivityRecord = record

        if isNewRecord,
           (record.agent != .codex || record.state != .working || record.isLegacy) {
            clearCodexUserSelectorOverride()
        }

        resolveAgentActivityState()
    }

    func updateVisibleTerminalSnapshot(_ snapshot: TerminalRenderSnapshot) {
        updateVisibleTerminalSnapshot(snapshot, visibleText: { snapshot.plainText })
    }

    func updateVisibleTerminalSnapshot(_: TerminalRenderSnapshot, visibleText: () -> String) {
        guard isStructuredCodexWorkingHook
        else {
            clearCodexUserSelectorOverride()
            return
        }

        let isVisibleUserSelector = CodexTerminalUserSelectorDetector.isUserSelectorVisible(in: visibleText())
        if isVisibleUserSelector {
            scheduleCodexUserSelectorConfirmationIfNeeded()
        } else {
            clearCodexUserSelectorOverride()
        }
    }

    private func resetAgentActivityState() {
        hookActivityRecord = TerminalAgentActivityRecord(agent: .unknown, state: .idle, isLegacy: true)
        clearCodexUserSelectorOverride()
        resolveAgentActivityState()
    }

    private var isStructuredCodexWorkingHook: Bool {
        hookActivityRecord.agent == .codex &&
            hookActivityRecord.state == .working &&
            hookActivityRecord.isLegacy == false
    }

    private func scheduleCodexUserSelectorConfirmationIfNeeded() {
        guard hasConfirmedCodexVisibleUserSelector == false,
              pendingCodexUserSelectorTask == nil
        else {
            return
        }

        codexUserSelectorGeneration += 1
        let generation = codexUserSelectorGeneration
        pendingCodexUserSelectorTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.codexSelectorDwellNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self,
                  self.codexUserSelectorGeneration == generation,
                  self.isStructuredCodexWorkingHook
            else {
                return
            }

            self.pendingCodexUserSelectorTask = nil
            self.setConfirmedCodexVisibleUserSelector(true)
        }
    }

    private func clearCodexUserSelectorOverride() {
        pendingCodexUserSelectorTask?.cancel()
        pendingCodexUserSelectorTask = nil
        codexUserSelectorGeneration += 1
        setConfirmedCodexVisibleUserSelector(false)
    }

    private func setConfirmedCodexVisibleUserSelector(_ isVisible: Bool) {
        guard hasConfirmedCodexVisibleUserSelector != isVisible else { return }

        hasConfirmedCodexVisibleUserSelector = isVisible
        resolveAgentActivityState()
    }

    private func resolveAgentActivityState() {
        let resolvedAgent = hookActivityRecord.agent == .unknown ? nil : hookActivityRecord.agent
        if activeAgent != resolvedAgent {
            activeAgent = resolvedAgent
        }

        let resolvedState: TerminalAgentActivityState
        if hookActivityRecord.agent == .codex,
           hookActivityRecord.state == .working,
           hookActivityRecord.isLegacy == false,
           hasConfirmedCodexVisibleUserSelector {
            resolvedState = .attention
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
