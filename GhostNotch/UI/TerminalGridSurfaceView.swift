import AppKit
import SwiftUI

struct TerminalGridSurfaceView: NSViewRepresentable {
    let snapshot: TerminalRenderSnapshot
    let initialLastReportedResize: TerminalGridResize?
    let allowsResizeReporting: Bool
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onKeyEvent: (TerminalKeyEvent) -> Void
    let onScroll: (Int) -> Void
    let onResize: (Int, Int, Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalGridView {
        let view = TerminalGridView()
        view.lastReportedResize = initialLastReportedResize
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        view.allowsResizeReporting = allowsResizeReporting
        view.onMovedToWindow = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator, coordinator.shouldRetryFocusOnWindowAttach else {
                return
            }
            Self.applyFocus(to: view, coordinator: coordinator)
        }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TerminalGridView, context: Context) {
        view.snapshot = snapshot
        view.onInput = onInput
        view.onKeyEvent = onKeyEvent
        view.onScroll = onScroll
        view.onResize = onResize
        view.allowsResizeReporting = allowsResizeReporting
        view.needsDisplay = true
        if allowsResizeReporting {
            view.reportSizeIfNeeded()
        }

        guard context.coordinator.lastFocusRequestID != focusRequestID else {
            return
        }

        context.coordinator.lastFocusRequestID = focusRequestID
        Self.applyFocus(to: view, coordinator: context.coordinator)
    }

    private static func applyFocus(to view: TerminalGridView, coordinator: Coordinator) {
        let attempt: () -> Bool = {
            guard let window = view.window else {
                return false
            }
            return window.makeFirstResponder(view)
        }

        if attempt() {
            coordinator.shouldRetryFocusOnWindowAttach = false
            return
        }

        coordinator.shouldRetryFocusOnWindowAttach = true
        DispatchQueue.main.async {
            if attempt() {
                coordinator.shouldRetryFocusOnWindowAttach = false
            }
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: TerminalGridView?
        var lastFocusRequestID = 0
        var shouldRetryFocusOnWindowAttach = false
    }
}
