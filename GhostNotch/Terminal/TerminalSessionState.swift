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

struct TerminalAgentProcessIdentity: Equatable, Sendable {
    let agent: TerminalAgentActivityAgent
    let processID: Int32
}

private struct TerminalAgentStatusEvidence {
    var text = ""
    var textSequence: UInt64 = 0
    var title: String?
    var titleSequence: UInt64 = 0
    var progress: String?
    var progressSequence: UInt64 = 0

    init() {}

    init(snapshot: TerminalRenderSnapshot) {
        text = snapshot.agentStatusText
        textSequence = snapshot.agentStatusTextSequence
        title = snapshot.terminalTitle
        titleSequence = snapshot.terminalTitleSequence
        progress = snapshot.terminalProgress
        progressSequence = snapshot.terminalProgressSequence
    }
}

private enum TerminalAgentScreenDetection {
    case state(TerminalAgentActivityState, visibleIdle: Bool = false)
    case preserve
}

private enum TerminalAgentScreenRules {
    static func detect(
        agent: TerminalAgentActivityAgent,
        text: String,
        title: String?,
        progress: String?
    ) -> TerminalAgentScreenDetection {
        switch agent {
        case .codex:
            codex(text: text, title: title)
        case .claude:
            claude(text: text, title: title, progress: progress)
        case .unknown:
            .state(.idle)
        }
    }

    private static func codex(text: String, title: String?) -> TerminalAgentScreenDetection {
        let normalizedTitle = title?.lowercased() ?? ""
        let normalizedText = text.lowercased()
        let bottom = bottomLines(in: normalizedText)

        if normalizedTitle.contains("action required") {
            return .state(.attention)
        }
        if containsBrailleSpinner(title) {
            return .state(.working)
        }
        if isCodexReadyPromptVisible(bottom) {
            return .state(.idle, visibleIdle: true)
        }
        if isTranscriptViewer(bottom) {
            return .preserve
        }
        if CodexTerminalUserSelectorDetector.isUserSelectorVisible(in: bottom) ||
            bottom.contains("enter to submit answer") ||
            bottom.contains("enter to submit all") ||
            bottom.contains("allow command?") ||
            (bottom.contains("press enter to confirm") && bottom.contains("esc to")) ||
            ((bottom.contains("do you want to") || bottom.contains("would you like to")) &&
                (bottom.contains("[y/n]") || bottom.contains("yes (y)"))) {
            return .state(.attention)
        }
        if !normalizedTitle.isEmpty {
            return .state(.idle, visibleIdle: true)
        }
        return .state(.idle)
    }

    private static func claude(
        text: String,
        title: String?,
        progress: String?
    ) -> TerminalAgentScreenDetection {
        let normalizedTitle = title?.lowercased() ?? ""
        let normalizedText = text.lowercased()
        let bottom = bottomLines(in: normalizedText)
        let lastLine = bottom.split(separator: "\n", omittingEmptySubsequences: true).last?
            .trimmingCharacters(in: .whitespaces) ?? ""

        if containsBrailleSpinner(title) {
            return .state(.working)
        }
        if bottom.contains("/btw") && bottom.contains("esc to close") {
            return .state(.working)
        }
        if isTranscriptViewer(bottom) ||
            (bottom.contains("select model") && bottom.contains("enter to select")) {
            return .preserve
        }
        if lastLine == "❯" {
            return .state(.idle, visibleIdle: true)
        }
        if (bottom.contains("enter to select") && bottom.contains("esc to cancel")) ||
            bottom.contains("do you want to proceed?") ||
            (bottom.contains("permission") && bottom.contains("allow")) ||
            ((bottom.contains("do you want to") || bottom.contains("would you like to")) &&
                bottom.contains("yes") && bottom.contains("no")) {
            return .state(.attention)
        }
        if bottom.contains("❯") && !bottom.contains("enter to select") {
            return .state(.idle, visibleIdle: true)
        }
        if normalizedTitle == "✳" {
            return .state(.idle, visibleIdle: true)
        }
        if progress?.trimmingCharacters(in: CharacterSet(charactersIn: ";")) == "4;0" {
            return .state(.idle)
        }
        return .state(.idle)
    }

    private static func containsBrailleSpinner(_ text: String?) -> Bool {
        text?.unicodeScalars.contains(where: { (0x2800...0x28FF).contains($0.value) }) == true
    }

    private static func isCodexReadyPromptVisible(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.last == "›" {
            return true
        }
        guard lines.last == "? for shortcuts" else {
            return false
        }

        return lines.dropLast().contains(where: { $0.first == "›" })
    }

    private static func isTranscriptViewer(_ text: String) -> Bool {
        text.contains("transcript") && text.contains("esc to close")
    }

    private static func bottomLines(in text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(8)
            .joined(separator: "\n")
    }
}

private struct TerminalAgentStatusDetector {
    private let startupGrace: TimeInterval
    private let idleConfirmationInterval: TimeInterval
    private let idleConfirmationCap: TimeInterval

    private(set) var process: TerminalAgentProcessIdentity?
    private(set) var state: TerminalAgentActivityState = .idle
    private(set) var needsFastRefresh = false
    private var evidence = TerminalAgentStatusEvidence()
    private var graceUntil: Date?
    private var sequenceFloor = TerminalAgentStatusEvidence()
    private var lastProcessObservationEvidence = TerminalAgentStatusEvidence()
    private var pendingIdleStartedAt: Date?
    private var lastIdleConfirmationAt: Date?
    private var idleConfirmations = 0

    init(
        startupGrace: TimeInterval,
        idleConfirmationInterval: TimeInterval,
        idleConfirmationCap: TimeInterval
    ) {
        self.startupGrace = startupGrace
        self.idleConfirmationInterval = idleConfirmationInterval
        self.idleConfirmationCap = idleConfirmationCap
    }

    mutating func updateProcess(_ nextProcess: TerminalAgentProcessIdentity?, now: Date) {
        guard process != nextProcess else {
            lastProcessObservationEvidence = evidence
            return
        }

        process = nextProcess
        state = .idle
        sequenceFloor = lastProcessObservationEvidence
        lastProcessObservationEvidence = evidence
        graceUntil = nextProcess == nil ? nil : now.addingTimeInterval(startupGrace)
        clearPendingIdle()
    }

    mutating func updateEvidence(_ nextEvidence: TerminalAgentStatusEvidence, now: Date) {
        evidence = nextEvidence
        evaluate(now: now)
    }

    mutating func refresh(now: Date) {
        evaluate(now: now)
    }

    private mutating func evaluate(now: Date) {
        guard let process else {
            state = .idle
            clearPendingIdle()
            return
        }
        if let graceUntil, now < graceUntil {
            state = .idle
            clearPendingIdle()
            return
        }
        graceUntil = nil

        let text = evidence.textSequence > sequenceFloor.textSequence ? evidence.text : ""
        let title = evidence.titleSequence > sequenceFloor.titleSequence ? evidence.title : nil
        let progress = evidence.progressSequence > sequenceFloor.progressSequence ? evidence.progress : nil
        switch TerminalAgentScreenRules.detect(
            agent: process.agent,
            text: text,
            title: title,
            progress: progress
        ) {
        case .preserve:
            clearPendingIdle()
        case .state(let nextState, let visibleIdle):
            apply(nextState, visibleIdle: visibleIdle, now: now)
        }
    }

    private mutating func apply(
        _ nextState: TerminalAgentActivityState,
        visibleIdle: Bool,
        now: Date
    ) {
        guard state == .working, nextState == .idle, !visibleIdle else {
            state = nextState
            clearPendingIdle()
            return
        }

        guard let startedAt = pendingIdleStartedAt else {
            pendingIdleStartedAt = now
            lastIdleConfirmationAt = now
            idleConfirmations = 0
            needsFastRefresh = true
            return
        }

        if now.timeIntervalSince(startedAt) >= idleConfirmationCap {
            state = .idle
            clearPendingIdle()
            return
        }

        guard let lastConfirmation = lastIdleConfirmationAt,
              now.timeIntervalSince(lastConfirmation) >= idleConfirmationInterval
        else {
            needsFastRefresh = true
            return
        }

        lastIdleConfirmationAt = now
        idleConfirmations += 1
        if idleConfirmations >= 3 {
            state = .idle
            clearPendingIdle()
        } else {
            needsFastRefresh = true
        }
    }

    private mutating func clearPendingIdle() {
        pendingIdleStartedAt = nil
        lastIdleConfirmationAt = nil
        idleConfirmations = 0
        needsFastRefresh = false
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
    private let startupGrace: TimeInterval
    private let idleConfirmationInterval: TimeInterval
    private let idleConfirmationCap: TimeInterval
    private var detector: TerminalAgentStatusDetector

    init(
        outputLimit: Int? = nil,
        agentStartupGrace: TimeInterval = 3,
        idleConfirmationInterval: TimeInterval = 0.1,
        idleConfirmationCap: TimeInterval = 0.7
    ) {
        outputCaptureLimit = outputLimit
        startupGrace = agentStartupGrace
        self.idleConfirmationInterval = idleConfirmationInterval
        self.idleConfirmationCap = idleConfirmationCap
        detector = TerminalAgentStatusDetector(
            startupGrace: agentStartupGrace,
            idleConfirmationInterval: idleConfirmationInterval,
            idleConfirmationCap: idleConfirmationCap
        )
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

    var activeAgentProcessIdentity: TerminalAgentProcessIdentity? {
        detector.process
    }

    var agentStatusNeedsFastRefresh: Bool {
        detector.needsFastRefresh
    }

    func updateDetectedAgentProcess(
        _ process: TerminalAgentProcessIdentity?,
        now: Date = Date()
    ) {
        detector.updateProcess(process, now: now)
        publishDetectedAgentStatus()
    }

    func updateVisibleTerminalSnapshot(
        _ snapshot: TerminalRenderSnapshot,
        now: Date = Date()
    ) {
        detector.updateEvidence(TerminalAgentStatusEvidence(snapshot: snapshot), now: now)
        publishDetectedAgentStatus()
    }

    func refreshAgentStatus(now: Date = Date()) {
        detector.refresh(now: now)
        publishDetectedAgentStatus()
    }

    private func resetAgentActivityState() {
        detector = TerminalAgentStatusDetector(
            startupGrace: startupGrace,
            idleConfirmationInterval: idleConfirmationInterval,
            idleConfirmationCap: idleConfirmationCap
        )
        publishDetectedAgentStatus()
    }

    private func publishDetectedAgentStatus() {
        let nextAgent = detector.process?.agent
        if activeAgent != nextAgent {
            activeAgent = nextAgent
        }
        if agentActivityState != detector.state {
            agentActivityState = detector.state
        }
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
