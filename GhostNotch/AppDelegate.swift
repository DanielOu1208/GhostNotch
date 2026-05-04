import AppKit
import Carbon

private let notchColorHotKeySignature = OSType(0x4E544347)
private let notchColorHotKeyID = UInt32(1)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var islandController: IslandPanelController?
    private var notchColorHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBarItem()
        setupNotchColorHotKey()

        let controller = IslandPanelController()
        islandController = controller
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tearDownNotchColorHotKey()
        islandController?.tearDown()
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ">_"
        item.button?.toolTip = "GhostNotch"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open GhostNotch", action: #selector(openGhostNotch), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let colorItem = NSMenuItem(title: "Toggle Notch Test Color", action: #selector(toggleNotchColor), keyEquivalent: "g")
        colorItem.keyEquivalentModifierMask = [.command, .option]
        colorItem.target = self
        menu.addItem(colorItem)
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

    @objc private func toggleNotchColor() {
        islandController?.toggleNotchFillMode()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupNotchColorHotKey() {
        var hotKeyID = EventHotKeyID(signature: notchColorHotKeySignature, id: notchColorHotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &notchColorHotKey
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
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
                      pressedHotKeyID.signature == notchColorHotKeySignature,
                      pressedHotKeyID.id == notchColorHotKeyID else {
                    return noErr
                }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    appDelegate.toggleNotchColor()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
    }

    private func tearDownNotchColorHotKey() {
        if let notchColorHotKey {
            UnregisterEventHotKey(notchColorHotKey)
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }
}
