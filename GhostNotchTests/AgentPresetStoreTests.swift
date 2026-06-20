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
