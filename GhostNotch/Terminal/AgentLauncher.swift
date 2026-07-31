import Foundation

struct AgentLauncher: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
        case codex
        case claude
        case opencode
        case cursor
        case omp
        case pi
        case droid
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

    static let opencode = AgentLauncher(
        id: .opencode,
        command: "opencode",
        displayName: "OpenCode",
        assetName: "OpenCodeLogo"
    )

    static let cursor = AgentLauncher(
        id: .cursor,
        command: "cursor-agent",
        displayName: "Cursor",
        assetName: "CursorLogo"
    )

    static let omp = AgentLauncher(
        id: .omp,
        command: "omp",
        displayName: "OMP",
        assetName: "OMPLogo"
    )

    static let pi = AgentLauncher(
        id: .pi,
        command: "pi",
        displayName: "Pi",
        assetName: "PiLogo"
    )

    static let droid = AgentLauncher(
        id: .droid,
        command: "droid",
        displayName: "Droid",
        assetName: "DroidLogo"
    )

    static let all: [AgentLauncher] = [
        codex,
        claude,
        opencode,
        cursor,
        omp,
        pi,
        droid,
    ]

    static func launcher(for id: ID) -> AgentLauncher? {
        all.first { $0.id == id }
    }

    static func launchers(for enabledIDs: [ID]) -> [AgentLauncher] {
        enabledIDs.compactMap(launcher(for:))
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
        selectedAgentID: AgentLauncher.ID?,
        enabledAgentIDs: [AgentLauncher.ID]
    ) -> HoverPrimaryAction {
        guard let selectedAgentID,
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
