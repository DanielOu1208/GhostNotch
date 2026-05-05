import AppKit
import SwiftUI

struct IslandExpandedView: View {
    @ObservedObject var sessionState: TerminalSessionState

    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 38)

            header

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            TerminalSurfaceView(
                output: terminalText,
                focusRequestID: focusRequestID,
                onInput: onInput,
                onResize: onResize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.45), radius: 5)

            Text("GhostNotch")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))

            Spacer()

            Text("Esc")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }

    private var terminalText: String {
        if let lastError = sessionState.lastError {
            return "GhostNotch terminal error:\n\(lastError)\n"
        }

        if sessionState.outputText.isEmpty {
            return sessionState.isRunning ? "Starting shell...\n" : "Shell stopped.\n"
        }

        return sessionState.outputText
    }

    private var statusColor: Color {
        sessionState.lastError == nil && sessionState.isRunning ? .green : .orange
    }

    private var statusText: String {
        if sessionState.lastError != nil {
            return "terminal error"
        }

        return sessionState.isRunning ? "default shell" : "starting shell"
    }
}

private struct TerminalSurfaceView: NSViewRepresentable {
    let output: String
    let focusRequestID: Int
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TerminalTextView()
        textView.onInput = onInput
        textView.onResize = onResize
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.86)
        textView.insertionPointColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindPanel = false
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize

        guard let textView = context.coordinator.textView else {
            return
        }

        textView.onInput = onInput
        textView.onResize = onResize

        if textView.string != output {
            textView.string = output
            textView.textColor = NSColor.white.withAlphaComponent(0.86)
            textView.setSelectedRange(NSRange(location: (output as NSString).length, length: 0))
            textView.scrollToEndOfDocument(nil)
        }

        context.coordinator.reportSizeIfNeeded(for: textView)

        guard context.coordinator.lastFocusRequestID != focusRequestID else {
            return
        }

        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator {
        weak var textView: TerminalTextView?
        var onInput: (Data) -> Void
        var onResize: (Int, Int) -> Void
        var lastFocusRequestID = 0
        private var lastReportedSize: NSSize = .zero

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func reportSizeIfNeeded(for textView: TerminalTextView) {
            let visibleSize = textView.enclosingScrollView?.contentView.bounds.size ?? textView.bounds.size
            guard visibleSize.width > 0, visibleSize.height > 0 else {
                return
            }

            guard abs(visibleSize.width - lastReportedSize.width) >= 8 ||
                  abs(visibleSize.height - lastReportedSize.height) >= 8 else {
                return
            }

            lastReportedSize = visibleSize
            let cols = Int(max(2, floor((visibleSize.width - 8) / 7.8)))
            let rows = Int(max(1, floor((visibleSize.height - 8) / 16.0)))
            onResize(cols, rows)
        }
    }
}

private final class TerminalTextView: NSTextView {
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            super.keyDown(with: event)
            return
        }

        guard let input = TerminalInputMapping.data(forKeyCode: UInt16(event.keyCode), characters: event.characters) else {
            return
        }

        onInput?(input)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text: String
        if let attributedString = insertString as? NSAttributedString {
            text = attributedString.string
        } else if let string = insertString as? String {
            text = string
        } else {
            text = ""
        }

        guard let input = TerminalInputMapping.data(forInsertedText: text) else {
            return
        }

        onInput?(input)
    }

    override func paste(_ sender: Any?) {
        guard let pastedText = NSPasteboard.general.string(forType: .string),
              let input = TerminalInputMapping.data(forInsertedText: pastedText) else {
            return
        }

        onInput?(input)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportResize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportResize()
    }

    private func reportResize() {
        let visibleSize = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        guard visibleSize.width > 0, visibleSize.height > 0 else {
            return
        }

        let cols = Int(max(2, floor((visibleSize.width - 8) / 7.8)))
        let rows = Int(max(1, floor((visibleSize.height - 8) / 16.0)))
        onResize?(cols, rows)
    }
}
