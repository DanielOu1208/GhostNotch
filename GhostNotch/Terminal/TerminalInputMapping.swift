import Foundation

/// Paste and legacy text helpers. Keyboard input uses `TerminalKeyEvent` and the rendering engine.
enum TerminalInputMapping {
    static func data(forInsertedText text: String) -> Data? {
        guard !text.isEmpty else {
            return nil
        }

        return text
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
            .data(using: .utf8)
    }

    static func data(forPastedText text: String, bracketed: Bool = false) -> Data? {
        GhosttyTerminalCore.encodePaste(text, bracketed: bracketed)
    }
}
