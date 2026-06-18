import Foundation

struct AgentLauncher: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case codex
        case claude
    }

    let id: ID
    let command: String
    let assetName: String
    let accessibilityLabel: String
    let helpText: String

    var commandLine: String {
        "\(command)\n"
    }

    static let codex = AgentLauncher(
        id: .codex,
        command: "codex",
        assetName: "OpenAILogo",
        accessibilityLabel: "Launch Codex",
        helpText: "Launch Codex"
    )

    static let claude = AgentLauncher(
        id: .claude,
        command: "claude",
        assetName: "ClaudeLogo",
        accessibilityLabel: "Launch Claude",
        helpText: "Launch Claude"
    )

    static let all: [AgentLauncher] = [
        codex,
        claude,
    ]
}
