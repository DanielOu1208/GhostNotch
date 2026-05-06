import AppKit
import SwiftUI

@MainActor
final class IslandPanel: NSPanel {
    var shouldAcceptKeyFocus = false
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        shouldAcceptKeyFocus
    }

    override var canBecomeMain: Bool {
        shouldAcceptKeyFocus
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !(firstResponder is TerminalGridView) {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }
}
