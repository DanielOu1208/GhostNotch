import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var islandController: IslandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBarItem()

        let controller = IslandPanelController()
        islandController = controller
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        islandController?.tearDown()
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ">_"
        item.button?.toolTip = "NotchTerm"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open NotchTerm", action: #selector(openNotchTerm), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    @objc private func openNotchTerm() {
        islandController?.expand()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
