import AppKit

@MainActor
final class OutsideClickMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let shouldCollapse: () -> Bool
    private let isPointInsidePanel: (NSPoint) -> Bool
    private let collapse: () -> Void

    init(
        shouldCollapse: @escaping () -> Bool,
        isPointInsidePanel: @escaping (NSPoint) -> Bool,
        collapse: @escaping () -> Void
    ) {
        self.shouldCollapse = shouldCollapse
        self.isPointInsidePanel = isPointInsidePanel
        self.collapse = collapse
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleClick(at: NSEvent.mouseLocation)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.handleClick(at: NSEvent.mouseLocation)
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        localMonitor = nil
        globalMonitor = nil
    }

    private func handleClick(at screenPoint: NSPoint) {
        guard shouldCollapse(), !isPointInsidePanel(screenPoint) else {
            return
        }

        collapse()
    }
}
