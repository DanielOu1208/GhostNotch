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
        XCTAssertFalse(AgentLauncher.codex.accessibilityLabel.isEmpty)
        XCTAssertFalse(AgentLauncher.claude.accessibilityLabel.isEmpty)
        XCTAssertFalse(AgentLauncher.codex.helpText.isEmpty)
        XCTAssertFalse(AgentLauncher.claude.helpText.isEmpty)
    }

    func testAgentLauncherBuildsDirectoryLaunchCommandWithShellEscapedPath() {
        XCTAssertEqual(
            AgentLauncher.codex.commandLine(directoryPath: "/Users/danielou/My Project"),
            "cd '/Users/danielou/My Project' && codex\n"
        )
        XCTAssertEqual(
            AgentLauncher.claude.commandLine(directoryPath: "/tmp/Daniel's Project"),
            "cd '/tmp/Daniel'\\''s Project' && claude\n"
        )
        XCTAssertEqual(
            AgentLauncher.codex.commandLine(directoryPath: "/tmp/$HOME && rm -rf nope"),
            "cd '/tmp/$HOME && rm -rf nope' && codex\n"
        )
    }
}
