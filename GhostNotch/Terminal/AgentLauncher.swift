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

    var commandLine: String {
        "\(command)\n"
    }

    static let codex = AgentLauncher(
        id: .codex,
        command: "codex",
        displayName: "Codex",
        assetName: "OpenAILogo"
    )

    static let claude = AgentLauncher(
        id: .claude,
        command: "claude",
        displayName: "Claude",
        assetName: "ClaudeLogo"
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

enum AgentLauncherSelection {
    static func toggled(
        currentSelection: AgentLauncher.ID?,
        selectedID: AgentLauncher.ID
    ) -> AgentLauncher.ID? {
        currentSelection == selectedID ? nil : selectedID
    }

    static func validated(
        _ selection: AgentLauncher.ID?,
        enabledIDs: [AgentLauncher.ID]
    ) -> AgentLauncher.ID? {
        selection.flatMap { enabledIDs.contains($0) ? $0 : nil }
    }
}

enum HoverPrimaryAction: Equatable {
    case expand
    case launch(AgentLauncher.ID)

    static func resolve(
        isTerminalRunning: Bool,
        selectedAgentID: AgentLauncher.ID?,
        enabledAgentIDs: [AgentLauncher.ID]
    ) -> HoverPrimaryAction {
        guard !isTerminalRunning,
              let selectedAgentID,
              enabledAgentIDs.contains(selectedAgentID) else {
            return .expand
        }
        return .launch(selectedAgentID)
    }

    func title(agentName: String? = nil, directoryName: String? = nil) -> String {
        let action = switch self {
        case .expand:
            agentName.map { "Expand \($0)" } ?? "Expand"
        case .launch:
            agentName.map { "Launch \($0)" } ?? "Launch"
        }

        return directoryName.map { "\(action) in \($0)" } ?? action
    }
}
