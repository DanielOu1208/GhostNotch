import AppKit
extension TerminalKeyEvent {
    init?(event: NSEvent) {
        let key = TerminalKey(keyCode: UInt16(event.keyCode), charactersIgnoringModifiers: event.charactersIgnoringModifiers)
        let text = TerminalKeyEvent.text(for: event, key: key)
        guard key != .unidentified || text?.isEmpty == false else {
            return nil
        }

        self.init(
            key: key,
            modifiers: TerminalKeyModifiers(event.modifierFlags),
            utf8: text,
            isRepeat: event.isARepeat
        )
    }

    private static func text(for event: NSEvent, key: TerminalKey) -> String? {
        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }

        switch key {
        case .enter, .tab, .backspace, .delete, .escape, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .home, .end, .pageUp, .pageDown, .function:
            return nil
        default:
            return characters
                .replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
        }
    }
}

extension TerminalKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: TerminalKeyModifiers = []
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        if filtered.contains(.shift) {
            modifiers.insert(.shift)
        }
        if filtered.contains(.control) {
            modifiers.insert(.control)
        }
        if filtered.contains(.option) {
            modifiers.insert(.option)
        }
        if filtered.contains(.command) {
            modifiers.insert(.command)
        }
        self = modifiers
    }
}

extension TerminalKey {
    init(keyCode: UInt16, charactersIgnoringModifiers: String?) {
        switch keyCode {
        case 36, 76:
            self = .enter
        case 48:
            self = .tab
        case 51:
            self = .backspace
        case 117:
            self = .delete
        case 53:
            self = .escape
        case 123:
            self = .arrowLeft
        case 124:
            self = .arrowRight
        case 125:
            self = .arrowDown
        case 126:
            self = .arrowUp
        case 115:
            self = .home
        case 119:
            self = .end
        case 116:
            self = .pageUp
        case 121:
            self = .pageDown
        case 49:
            self = .space
        case 122:
            self = .function(1)
        case 120:
            self = .function(2)
        case 99:
            self = .function(3)
        case 118:
            self = .function(4)
        case 96:
            self = .function(5)
        case 97:
            self = .function(6)
        case 98:
            self = .function(7)
        case 100:
            self = .function(8)
        case 101:
            self = .function(9)
        case 109:
            self = .function(10)
        case 103:
            self = .function(11)
        case 111:
            self = .function(12)
        default:
            if let letter = charactersIgnoringModifiers?.first, letter.isLetter {
                self = .letter(letter)
            } else {
                self = .unidentified
            }
        }
    }
}

extension TerminalColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}
