import XCTest

@MainActor
final class AgentLauncherTests: XCTestCase {
    func testAgentLauncherDefinitionsUsePlainCommandsAndAssets() {
        XCTAssertEqual(
            AgentLauncher.all.map(\.id),
            [.codex, .claude, .opencode, .cursor, .omp, .pi, .droid]
        )
        XCTAssertEqual(
            AgentLauncher.all.map(\.command),
            ["codex", "claude", "opencode", "cursor-agent", "omp", "pi", "droid"]
        )
        XCTAssertEqual(
            AgentLauncher.all.map(\.displayName),
            ["Codex", "Claude", "OpenCode", "Cursor", "OMP", "Pi", "Droid"]
        )
        XCTAssertEqual(
            AgentLauncher.all.map(\.assetName),
            [
                "OpenAILogo",
                "ClaudeLogo",
                "OpenCodeLogo",
                "CursorLogo",
                "OMPLogo",
                "PiLogo",
                "DroidLogo",
            ]
        )
        XCTAssertEqual(AgentLauncher.all.map(\.commandLine), [
            "codex\n",
            "claude\n",
            "opencode\n",
            "cursor-agent\n",
            "omp\n",
            "pi\n",
            "droid\n",
        ])
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
