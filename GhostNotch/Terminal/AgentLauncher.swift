import Foundation

struct AgentLauncher: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
        case codex
        case claude
    }

    let id: ID
    let command: String
    let displayName: String
    let assetName: String
    let accessibilityLabel: String
    let helpText: String

    var commandLine: String {
        "\(command)\n"
    }

    static let codex = AgentLauncher(
        id: .codex,
        command: "codex",
        displayName: "Codex",
        assetName: "OpenAILogo",
        accessibilityLabel: "Launch Codex",
        helpText: "Launch Codex"
    )

    static let claude = AgentLauncher(
        id: .claude,
        command: "claude",
        displayName: "Claude",
        assetName: "ClaudeLogo",
        accessibilityLabel: "Launch Claude",
        helpText: "Launch Claude"
    )

    static let all: [AgentLauncher] = [
        codex,
        claude,
    ]

    static func launchers(for enabledIDs: [ID]) -> [AgentLauncher] {
        enabledIDs.compactMap { enabledID in
            all.first { $0.id == enabledID }
        }
    }
}
