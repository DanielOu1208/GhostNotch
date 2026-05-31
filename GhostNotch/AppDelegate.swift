import AppKit
import Carbon

private let toggleHotKeySignature = OSType(0x544F474C)
private let toggleHotKeyID = UInt32(2)


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var islandController: IslandPanelController?
    private var toggleHotKey: EventHotKeyRef?
    private var toggleHotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBarItem()
        setupToggleHotKey()

        let controller = IslandPanelController()
        islandController = controller
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tearDownToggleHotKey()
        islandController?.tearDown()
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ">_"
        item.button?.toolTip = "GhostNotch"

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Toggle GhostNotch", action: #selector(toggleTerminal), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    @objc private func openGhostNotch() {
        islandController?.expand()
    }

    @objc private func toggleTerminal() {
        guard let islandController else { return }
        switch islandController.state {
        case .collapsed, .hover:
            islandController.expand()
        case .expanded:
            islandController.collapse()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupToggleHotKey() {
        let hotKeyID = EventHotKeyID(signature: toggleHotKeySignature, id: toggleHotKeyID)
        var registeredHotKey: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        guard hotKeyStatus == noErr, let registeredHotKey else {
            NSLog("GhostNotch failed to register toggle hotkey: \(hotKeyStatus)")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var pressedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr,
                      pressedHotKeyID.signature == toggleHotKeySignature,
                      pressedHotKeyID.id == toggleHotKeyID else {
                    return noErr
                }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    appDelegate.toggleTerminal()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard handlerStatus == noErr, let installedHandler else {
            NSLog("GhostNotch failed to install toggle hotkey handler: \(handlerStatus)")
            UnregisterEventHotKey(registeredHotKey)
            return
        }

        toggleHotKey = registeredHotKey
        toggleHotKeyHandler = installedHandler
    }

    private func tearDownToggleHotKey() {
        if let toggleHotKey {
            UnregisterEventHotKey(toggleHotKey)
        }

        if let toggleHotKeyHandler {
            RemoveEventHandler(toggleHotKeyHandler)
        }
    }

}
