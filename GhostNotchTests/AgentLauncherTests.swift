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
}
