import Foundation

/// Paste helpers. Keyboard input uses `TerminalKeyEvent` and the rendering engine.
enum TerminalInputMapping {
    static func data(forPastedText text: String, bracketed: Bool = false) -> Data? {
        GhosttyTerminalCore.encodePaste(text, bracketed: bracketed)
    }
}
