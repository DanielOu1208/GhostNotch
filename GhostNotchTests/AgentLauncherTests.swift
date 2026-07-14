import XCTest

@MainActor
final class AgentLauncherTests: XCTestCase {
    func testAgentLauncherDefinitionsUsePlainCommandsAndAssets() {
        XCTAssertEqual(AgentLauncher.all.map(\.id), [.codex, .claude])
        XCTAssertEqual(AgentLauncher.codex.command, "codex")
        XCTAssertEqual(AgentLauncher.claude.command, "claude")
        XCTAssertEqual(AgentLauncher.codex.displayName, "Codex")
        XCTAssertEqual(AgentLauncher.claude.displayName, "Claude")
        XCTAssertEqual(AgentLauncher.codex.commandLine, "codex\n")
        XCTAssertEqual(AgentLauncher.claude.commandLine, "claude\n")
        XCTAssertEqual(AgentLauncher.codex.assetName, "OpenAILogo")
        XCTAssertEqual(AgentLauncher.claude.assetName, "ClaudeLogo")
    }

    func testAgentSelectionTogglesReplacesAndValidates() {
        XCTAssertEqual(
            AgentLauncherSelection.toggled(currentSelection: nil, selectedID: .codex),
            .codex
        )
        XCTAssertNil(
            AgentLauncherSelection.toggled(currentSelection: .codex, selectedID: .codex)
        )
        XCTAssertEqual(
            AgentLauncherSelection.toggled(currentSelection: .codex, selectedID: .claude),
            .claude
        )
        XCTAssertNil(AgentLauncherSelection.validated(.claude, enabledIDs: [.codex]))
    }

    func testHoverPrimaryActionRequiresValidSelectionToLaunch() {
        XCTAssertEqual(
            HoverPrimaryAction.resolve(
                selectedAgentID: nil,
                enabledAgentIDs: [.codex]
            ),
            .expand
        )
        XCTAssertEqual(
            HoverPrimaryAction.resolve(
                selectedAgentID: .claude,
                enabledAgentIDs: [.codex]
            ),
            .expand
        )
        XCTAssertEqual(
            HoverPrimaryAction.resolve(
                selectedAgentID: .claude,
                enabledAgentIDs: [.codex, .claude]
            ),
            .launch(.claude)
        )
    }

    func testHoverPrimaryActionTitlesIncludeAgentAndSelectedDirectory() {
        XCTAssertEqual(HoverPrimaryAction.expand.title(), "Expand")
        XCTAssertEqual(
            HoverPrimaryAction.expand.title(agentName: "Codex"),
            "Expand Codex"
        )
        XCTAssertEqual(
            HoverPrimaryAction.expand.title(directoryName: "GhostNotch"),
            "Expand in GhostNotch"
        )
        XCTAssertEqual(
            HoverPrimaryAction.launch(.claude).title(
                agentName: "Claude",
                directoryName: "Website"
            ),
            "Launch Claude in Website"
        )
    }
}
