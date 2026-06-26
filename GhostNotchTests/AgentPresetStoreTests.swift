import XCTest

@MainActor
final class AgentPresetStoreTests: XCTestCase {
    func testStoreDefaultsToAllAgentsAndNoDirectoryPresets() {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = AgentPresetStore(userDefaults: userDefaults)

        XCTAssertEqual(store.directoryPresets, [])
        XCTAssertEqual(store.enabledAgentIDs, [.codex, .claude])
        XCTAssertEqual(store.enabledLaunchers.map(\.id), [.codex, .claude])
    }

    func testStoreLimitsDirectoryPresetsToThree() {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = AgentPresetStore(userDefaults: userDefaults)

        store.addDirectoryPreset(label: "One", path: "/tmp/one")
        store.addDirectoryPreset(label: "Two", path: "/tmp/two")
        store.addDirectoryPreset(label: "Three", path: "/tmp/three")
        store.addDirectoryPreset(label: "Four", path: "/tmp/four")

        XCTAssertEqual(store.directoryPresets.map(\.label), ["One", "Two", "Three"])
    }

    func testStorePersistsConfiguration() {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let firstStore = AgentPresetStore(userDefaults: userDefaults)
        firstStore.addDirectoryPreset(label: "GhostNotch", path: "/tmp/GhostNotch")
        firstStore.setAgent(.claude, isEnabled: false)

        let secondStore = AgentPresetStore(userDefaults: userDefaults)

        XCTAssertEqual(secondStore.directoryPresets.map(\.label), ["GhostNotch"])
        XCTAssertEqual(secondStore.directoryPresets.map(\.path), ["/tmp/GhostNotch"])
        XCTAssertEqual(secondStore.enabledAgentIDs, [.codex])
    }

    func testStorePersistsDirectoryPresetIcon() {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let firstStore = AgentPresetStore(userDefaults: userDefaults)
        firstStore.addDirectoryPreset(label: "GhostNotch", path: "/tmp/GhostNotch", icon: "GN")

        let secondStore = AgentPresetStore(userDefaults: userDefaults)

        XCTAssertEqual(secondStore.directoryPresets.map(\.icon), ["GN"])
        XCTAssertEqual(secondStore.directoryPresets.map(\.displayIcon), ["GN"])
    }

    func testStoreLoadsLegacyConfigurationWithoutDirectoryPresetIcon() throws {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let presetID = UUID()
        let legacyConfigurationJSON = """
        {
          "directoryPresets": [
            {
              "id": "\(presetID.uuidString)",
              "label": "GhostNotch",
              "path": "/tmp/GhostNotch"
            }
          ],
          "enabledAgentIDs": ["codex"]
        }
        """
        userDefaults.set(Data(legacyConfigurationJSON.utf8), forKey: "AgentPresetConfiguration.v1")

        let store = AgentPresetStore(userDefaults: userDefaults)

        let preset = try XCTUnwrap(store.directoryPresets.first)
        XCTAssertEqual(preset.id, presetID)
        XCTAssertEqual(preset.icon, "")
        XCTAssertEqual(preset.displayIcon, "GN")
        XCTAssertEqual(store.enabledAgentIDs, [.codex])
    }

    func testDirectoryPresetIconSanitizesInput() {
        XCTAssertEqual(AgentLaunchDirectoryPreset.sanitizedIcon("  API  "), "API")
        XCTAssertEqual(AgentLaunchDirectoryPreset.sanitizedIcon("abcd"), "abc")
        XCTAssertEqual(AgentLaunchDirectoryPreset.sanitizedIcon("🚀Launch"), "🚀")
    }

    func testDirectoryPresetDisplayIconUsesAutomaticInitialsWhenIconIsBlank() {
        XCTAssertEqual(
            AgentLaunchDirectoryPreset(label: "Project Docs", path: "/tmp/project-docs").displayIcon,
            "PD"
        )
        XCTAssertEqual(
            AgentLaunchDirectoryPreset(label: "GhostNotch", path: "/tmp/GhostNotch").displayIcon,
            "GN"
        )
        XCTAssertEqual(
            AgentLaunchDirectoryPreset(label: "", path: "/tmp/web-final").displayIcon,
            "WF"
        )
    }

    func testAgentFilteringPreservesEnabledOrder() {
        let (userDefaults, suiteName) = makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = AgentPresetStore(userDefaults: userDefaults)
        store.loadConfiguration(
            AgentPresetConfiguration(
                directoryPresets: [],
                enabledAgentIDs: [.claude, .codex, .claude]
            )
        )

        XCTAssertEqual(store.enabledLaunchers.map(\.id), [.claude, .codex])
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "GhostNotchTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}

final class IslandMetricsTests: XCTestCase {
    func testHoverHeightLeavesControlsBelowPhysicalNotch() {
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 38), 90)
    }

    func testHoverHeightUsesMinimumForShortOrMissingNotch() {
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 0), 88)
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 20), 88)
    }
}
