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
        XCTAssertEqual(secondStore.directoryPresets.map { displayIcon(for: $0) }, ["GN"])
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
        XCTAssertEqual(DirectoryPresetIcon.displayValue(icon: preset.icon, fallbackSource: preset.displayLabel), "GN")
        XCTAssertEqual(store.enabledAgentIDs, [.codex])
    }

    func testDirectoryPresetIconSanitizesInput() {
        XCTAssertEqual(DirectoryPresetIcon.sanitized("  API  "), "API")
        XCTAssertEqual(DirectoryPresetIcon.sanitized("abcd"), "abc")
        XCTAssertEqual(DirectoryPresetIcon.sanitized("1234"), "123")
        XCTAssertEqual(DirectoryPresetIcon.sanitized("🚀Launch"), "🚀")
        XCTAssertEqual(DirectoryPresetIcon.sanitized("☕️Coffee"), "☕️")
    }

    func testDirectoryPresetDisplayIconUsesAutomaticInitialsWhenIconIsBlank() {
        XCTAssertEqual(
            displayIcon(for: AgentLaunchDirectoryPreset(label: "Project Docs", path: "/tmp/project-docs")),
            "PD"
        )
        XCTAssertEqual(
            displayIcon(for: AgentLaunchDirectoryPreset(label: "GhostNotch", path: "/tmp/GhostNotch")),
            "GN"
        )
        XCTAssertEqual(
            displayIcon(for: AgentLaunchDirectoryPreset(label: "", path: "/tmp/web-final")),
            "WF"
        )
    }

    func testDirectoryPresetDisplayIconUsesStoredIconWhenPresent() {
        let preset = AgentLaunchDirectoryPreset(label: "GhostNotch", path: "/tmp/GhostNotch", icon: "gn")

        XCTAssertEqual(displayIcon(for: preset), "gn")
    }

    func testDirectoryPresetSelectionTogglesFromNoSelection() {
        let presetID = UUID()

        XCTAssertEqual(
            DirectoryPresetSelection.toggled(currentSelection: nil, selectedPresetID: presetID),
            presetID
        )
    }

    func testDirectoryPresetSelectionClearsMatchingSelection() {
        let presetID = UUID()

        XCTAssertNil(
            DirectoryPresetSelection.toggled(currentSelection: presetID, selectedPresetID: presetID)
        )
    }

    func testDirectoryPresetSelectionReplacesDifferentSelection() {
        let firstPresetID = UUID()
        let secondPresetID = UUID()

        XCTAssertEqual(
            DirectoryPresetSelection.toggled(currentSelection: firstPresetID, selectedPresetID: secondPresetID),
            secondPresetID
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

    private func displayIcon(for preset: AgentLaunchDirectoryPreset) -> String {
        DirectoryPresetIcon.displayValue(icon: preset.icon, fallbackSource: preset.displayLabel)
    }
}

final class IslandMetricsTests: XCTestCase {
    func testHoverHeightLeavesControlsBelowPhysicalNotch() {
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 38), 112)
    }

    func testHoverHeightUsesMinimumForShortOrMissingNotch() {
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 0), 112)
        XCTAssertEqual(IslandMetrics.hoverHeight(forNotchHeight: 20), 112)
    }
}

final class IslandTransitionPlanTests: XCTestCase {
    func testStandardTransitionTimingsAndCurves() {
        let cases: [(IslandState, IslandState, TimeInterval, IslandTransitionCurve)] = [
            (.collapsed, .hover, 0.22, .spring),
            (.hover, .collapsed, 0.18, .easeOut),
            (.collapsed, .expanded, 0.34, .spring),
            (.hover, .expanded, 0.34, .spring),
            (.expanded, .collapsed, 0.22, .easeOut),
            (.expanded, .hover, 0.22, .easeOut),
        ]

        for (from, to, duration, curve) in cases {
            let plan = IslandTransitionPlan(from: from, to: to, reducesMotion: false)

            XCTAssertEqual(plan.duration, duration, accuracy: 0.001)
            XCTAssertEqual(plan.curve, curve)
        }
        XCTAssertEqual(IslandTransitionPlan.hoverExitGrace, 0.04, accuracy: 0.001)
    }

    func testReduceMotionUsesShortCrossFadeForEveryTransition() {
        let plan = IslandTransitionPlan(from: .collapsed, to: .expanded, reducesMotion: true)

        XCTAssertEqual(plan.duration, 0.08, accuracy: 0.001)
        XCTAssertTrue(plan.reducesMotion)
        XCTAssertEqual(plan.curve, .easeOut)
    }

    func testExpandedSpringStartsFastAndSettlesAfterOneSmallOvershoot() {
        let plan = IslandTransitionPlan(from: .collapsed, to: .expanded, reducesMotion: false)
        let samples = stride(from: 0.0, through: plan.duration, by: 0.001).map(plan.progress(at:))

        XCTAssertEqual(plan.progress(at: 0), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(plan.progress(at: 0.06), 0.5)
        XCTAssertEqual(samples.max() ?? 0, 1.02, accuracy: 0.001)
        XCTAssertEqual(plan.progress(at: plan.duration), 1, accuracy: 0.0001)
    }

    func testHoverSpringStartsFastAndSettlesAfterOneSmallOvershoot() {
        let plan = IslandTransitionPlan(from: .collapsed, to: .hover, reducesMotion: false)
        let samples = stride(from: 0.0, through: plan.duration, by: 0.001).map(plan.progress(at:))

        XCTAssertEqual(plan.progress(at: 0), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(plan.progress(at: 0.04), 0.5)
        XCTAssertEqual(samples.max() ?? 0, 1.02, accuracy: 0.001)
        XCTAssertEqual(plan.progress(at: plan.duration), 1, accuracy: 0.0001)
    }

    func testEaseOutTransitionsNeverOvershoot() {
        let plan = IslandTransitionPlan(from: .expanded, to: .collapsed, reducesMotion: false)
        let samples = stride(from: 0.0, through: plan.duration, by: 0.001).map(plan.progress(at:))

        XCTAssertEqual(samples.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(samples.last ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(samples, samples.sorted())
        XCTAssertLessThanOrEqual(samples.max() ?? 0, 1)
    }

    func testTransitionFramesStayAttachedToScreenTopIncludingOvershoot() {
        let screenFrame = NSRect(x: 0, y: 0, width: 2_000, height: 1_000)
        let startFrame = NSRect(x: 860, y: 962, width: 280, height: 38)
        let targetFrame = NSRect(x: 588.6, y: 438, width: 822.8, height: 562)

        for progress: CGFloat in [0, 0.5, 1, 1.02] {
            let frame = WindowPositioner.transitionFrame(
                from: startFrame,
                to: targetFrame,
                progress: progress,
                screenFrame: screenFrame
            )

            XCTAssertEqual(frame.midX, screenFrame.midX, accuracy: 0.0001)
            XCTAssertEqual(frame.maxY, screenFrame.maxY, accuracy: 0.0001)
        }

        XCTAssertEqual(
            WindowPositioner.transitionFrame(
                from: startFrame,
                to: targetFrame,
                progress: 1,
                screenFrame: screenFrame
            ),
            targetFrame
        )
    }

    func testHoverHitTestingIncludesExactScreenTopEdge() {
        let frame = NSRect(x: 888, y: 1_291, width: 280, height: 38)

        XCTAssertTrue(
            WindowPositioner.containsHoverPoint(
                NSPoint(x: frame.midX, y: frame.maxY),
                in: frame
            )
        )
        XCTAssertTrue(
            WindowPositioner.containsHoverPoint(
                NSPoint(x: frame.midX, y: frame.maxY - 0.5),
                in: frame
            )
        )
        XCTAssertFalse(
            WindowPositioner.containsHoverPoint(
                NSPoint(x: frame.midX, y: frame.maxY + 0.5),
                in: frame
            )
        )
        XCTAssertFalse(
            WindowPositioner.containsHoverPoint(
                NSPoint(x: frame.maxX, y: frame.maxY),
                in: frame
            )
        )
    }

    func testCloseDestinationUsesFinalHoverBounds() {
        let hoverFrame = NSRect(x: 100, y: 100, width: 420, height: 112)

        XCTAssertEqual(
            IslandTransitionPlan.closeDestination(
                pointer: NSPoint(x: hoverFrame.midX, y: hoverFrame.midY),
                hoverFrame: hoverFrame
            ),
            .hover
        )
        XCTAssertEqual(
            IslandTransitionPlan.closeDestination(
                pointer: NSPoint(x: hoverFrame.midX, y: hoverFrame.maxY),
                hoverFrame: hoverFrame
            ),
            .hover
        )
        XCTAssertEqual(
            IslandTransitionPlan.closeDestination(pointer: .zero, hoverFrame: hoverFrame),
            .collapsed
        )
    }

    func testOnlyCurrentGenerationCanComplete() {
        let plan = IslandTransitionPlan(from: .collapsed, to: .expanded, reducesMotion: false)

        XCTAssertTrue(plan.canComplete(generation: 3, currentGeneration: 3, state: .expanded))
        XCTAssertFalse(plan.canComplete(generation: 2, currentGeneration: 3, state: .expanded))
        XCTAssertFalse(plan.canComplete(generation: 3, currentGeneration: 3, state: .collapsed))
    }
}
