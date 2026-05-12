import Foundation

final class GhosttyTerminalCore {
    var onWriteToPTY: ((Data) -> Void)?

    private(set) var columns: Int
    private(set) var rows: Int

    private var terminal: OpaquePointer?
    private var cachedSnapshot: TerminalRenderSnapshot

    init(columns: Int = 80, rows: Int = 18) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        cachedSnapshot = .empty(columns: self.columns, rows: self.rows)

        terminal = GNVTTerminalCreate(
            UInt16(self.columns),
            UInt16(self.rows),
            ghosttyTerminalWriteCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        refreshSnapshot()
    }

    deinit {
        GNVTTerminalDestroy(terminal)
    }

    var snapshot: TerminalRenderSnapshot {
        cachedSnapshot
    }

    func processOutput(_ data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            GNVTTerminalWrite(terminal, baseAddress, data.count)
        }
        refreshSnapshot()
    }

    func resize(columns newColumns: Int, rows newRows: Int) {
        columns = max(newColumns, 2)
        rows = max(newRows, 1)
        GNVTTerminalResize(terminal, UInt16(columns), UInt16(rows), 8, 16)
        refreshSnapshot()
    }

    func scrollViewport(deltaRows: Int) {
        GNVTTerminalScrollViewport(terminal, deltaRows)
        refreshSnapshot()
    }

    func scrollToBottom() {
        GNVTTerminalScrollToBottom(terminal)
        refreshSnapshot()
    }

    func encodeKey(_ event: TerminalKeyEvent) -> Data? {
        guard event.key != .unidentified || event.utf8?.isEmpty == false else {
            return nil
        }

        let encoded: Data? = event.utf8?.withCString { utf8Pointer in
            encodeKey(
                key: event.key,
                modifiers: event.modifiers,
                utf8Pointer: utf8Pointer,
                utf8Length: strlen(utf8Pointer),
                isRepeat: event.isRepeat
            )
        } ?? encodeKey(
            key: event.key,
            modifiers: event.modifiers,
            utf8Pointer: nil,
            utf8Length: 0,
            isRepeat: event.isRepeat
        )

        return encoded
    }

    func focusData() -> Data {
        Self.encodeFocus(focused: true)
    }

    func blurData() -> Data {
        Self.encodeFocus(focused: false)
    }

    static func encodePaste(_ text: String, bracketed: Bool = true) -> Data? {
        guard !text.isEmpty else {
            return nil
        }

        var input = text.utf8.map { CChar(bitPattern: $0) }
        var output = Array(repeating: CChar(0), count: input.count + 32)
        var written = 0

        let success = input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                GNVTPasteEncode(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    bracketed,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    &written
                )
            }
        }

        guard success else {
            return nil
        }

        return output.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: written)
        }
    }

    private static func encodeFocus(focused: Bool) -> Data {
        var output = Array(repeating: CChar(0), count: 16)
        var written = 0
        let success = output.withUnsafeMutableBufferPointer { outputBuffer in
            GNVTFocusEncode(focused, outputBuffer.baseAddress, outputBuffer.count, &written)
        }

        guard success else {
            return Data()
        }

        return output.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: written)
        }
    }

    private func refreshSnapshot() {
        var loadResult = loadSnapshot(graphemeCapacity: max(columns * rows * 2, 1))
        var retryCount = 0
        while !loadResult.success,
              loadResult.requiredGraphemeCount > loadResult.graphemes.count,
              retryCount < 2 {
            loadResult = loadSnapshot(graphemeCapacity: loadResult.requiredGraphemeCount)
            retryCount += 1
        }

        guard loadResult.success else {
            cachedSnapshot = .empty(columns: columns, rows: rows)
            return
        }

        let meta = loadResult.meta
        columns = Int(meta.columns)
        rows = Int(meta.rows)
        cachedSnapshot = TerminalRenderSnapshot(
            columns: columns,
            rows: rows,
            cells: loadResult.cells.map { TerminalCell(ghosttyCell: $0, graphemes: loadResult.graphemes) },
            cursorColumn: Int(meta.cursorColumn),
            cursorRow: Int(meta.cursorRow),
            cursorVisible: meta.cursorVisible,
            cursorBlinking: meta.cursorBlinking,
            cursorStyle: TerminalCursorStyle(rawValue: meta.cursorStyle) ?? .bar,
            isAlternateScreen: meta.isAlternateScreen,
            hasMouseTracking: meta.hasMouseTracking,
            totalRows: Int(meta.totalRows),
            scrollbackRows: Int(meta.scrollbackRows)
        )
    }

    private func loadSnapshot(graphemeCapacity: Int) -> GhosttySnapshotLoadResult {
        var cells = Array(repeating: GNVTCell.blank, count: columns * rows)
        var graphemes = Array(repeating: UInt32(0), count: max(graphemeCapacity, 1))
        var requiredGraphemeCount = 0
        var meta = GNVTSnapshotMeta()

        let success = cells.withUnsafeMutableBufferPointer { cellBuffer in
            graphemes.withUnsafeMutableBufferPointer { graphemeBuffer in
                GNVTTerminalSnapshot(
                    terminal,
                    cellBuffer.baseAddress,
                    cellBuffer.count,
                    graphemeBuffer.baseAddress,
                    graphemeBuffer.count,
                    &requiredGraphemeCount,
                    &meta
                )
            }
        }

        if requiredGraphemeCount < graphemes.count {
            graphemes.removeSubrange(requiredGraphemeCount..<graphemes.count)
        }

        return GhosttySnapshotLoadResult(
            success: success,
            cells: cells,
            graphemes: graphemes,
            requiredGraphemeCount: requiredGraphemeCount,
            meta: meta
        )
    }

    private func encodeKey(
        key: TerminalKey,
        modifiers: TerminalKeyModifiers,
        utf8Pointer: UnsafePointer<CChar>?,
        utf8Length: Int,
        isRepeat: Bool
    ) -> Data? {
        var output = Array(repeating: CChar(0), count: 128)
        var written = 0
        let success = output.withUnsafeMutableBufferPointer { outputBuffer in
            GNVTTerminalEncodeKey(
                terminal,
                key.ghosttyKey,
                modifiers.bridgeValue,
                utf8Pointer,
                utf8Length,
                isRepeat,
                outputBuffer.baseAddress,
                outputBuffer.count,
                &written
            )
        }

        guard success, written > 0 else {
            return nil
        }

        return output.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: written)
        }
    }

    fileprivate func handleWriteToPTY(bytes: UnsafePointer<UInt8>?, count: Int) {
        guard let bytes, count > 0 else {
            return
        }

        onWriteToPTY?(Data(bytes: bytes, count: count))
    }
}

private struct GhosttySnapshotLoadResult {
    let success: Bool
    let cells: [GNVTCell]
    let graphemes: [UInt32]
    let requiredGraphemeCount: Int
    let meta: GNVTSnapshotMeta
}

struct TerminalKeyEvent: Equatable {
    let key: TerminalKey
    let modifiers: TerminalKeyModifiers
    let utf8: String?
    let isRepeat: Bool
}

struct TerminalKeyModifiers: OptionSet, Equatable {
    let rawValue: UInt16

    static let shift = TerminalKeyModifiers(rawValue: UInt16(GNVT_MOD_SHIFT))
    static let control = TerminalKeyModifiers(rawValue: UInt16(GNVT_MOD_CONTROL))
    static let option = TerminalKeyModifiers(rawValue: UInt16(GNVT_MOD_OPTION))
    static let command = TerminalKeyModifiers(rawValue: UInt16(GNVT_MOD_COMMAND))

    var bridgeValue: UInt16 {
        rawValue
    }
}

enum TerminalKey: Equatable {
    case unidentified
    case escape
    case enter
    case tab
    case backspace
    case delete
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
    case space
    case letter(Character)
    case function(Int)

    var ghosttyKey: GNVTKey {
        switch self {
        case .unidentified: return GNVT_KEY_UNIDENTIFIED
        case .escape: return GNVT_KEY_ESCAPE
        case .enter: return GNVT_KEY_ENTER
        case .tab: return GNVT_KEY_TAB
        case .backspace: return GNVT_KEY_BACKSPACE
        case .delete: return GNVT_KEY_DELETE
        case .arrowUp: return GNVT_KEY_ARROW_UP
        case .arrowDown: return GNVT_KEY_ARROW_DOWN
        case .arrowLeft: return GNVT_KEY_ARROW_LEFT
        case .arrowRight: return GNVT_KEY_ARROW_RIGHT
        case .home: return GNVT_KEY_HOME
        case .end: return GNVT_KEY_END
        case .pageUp: return GNVT_KEY_PAGE_UP
        case .pageDown: return GNVT_KEY_PAGE_DOWN
        case .space: return GNVT_KEY_SPACE
        case .letter("a"), .letter("A"): return GNVT_KEY_A
        case .letter("b"), .letter("B"): return GNVT_KEY_B
        case .letter("c"), .letter("C"): return GNVT_KEY_C
        case .letter("d"), .letter("D"): return GNVT_KEY_D
        case .letter("e"), .letter("E"): return GNVT_KEY_E
        case .letter("f"), .letter("F"): return GNVT_KEY_F
        case .letter("g"), .letter("G"): return GNVT_KEY_G
        case .letter("h"), .letter("H"): return GNVT_KEY_H
        case .letter("i"), .letter("I"): return GNVT_KEY_I
        case .letter("j"), .letter("J"): return GNVT_KEY_J
        case .letter("k"), .letter("K"): return GNVT_KEY_K
        case .letter("l"), .letter("L"): return GNVT_KEY_L
        case .letter("m"), .letter("M"): return GNVT_KEY_M
        case .letter("n"), .letter("N"): return GNVT_KEY_N
        case .letter("o"), .letter("O"): return GNVT_KEY_O
        case .letter("p"), .letter("P"): return GNVT_KEY_P
        case .letter("q"), .letter("Q"): return GNVT_KEY_Q
        case .letter("r"), .letter("R"): return GNVT_KEY_R
        case .letter("s"), .letter("S"): return GNVT_KEY_S
        case .letter("t"), .letter("T"): return GNVT_KEY_T
        case .letter("u"), .letter("U"): return GNVT_KEY_U
        case .letter("v"), .letter("V"): return GNVT_KEY_V
        case .letter("w"), .letter("W"): return GNVT_KEY_W
        case .letter("x"), .letter("X"): return GNVT_KEY_X
        case .letter("y"), .letter("Y"): return GNVT_KEY_Y
        case .letter("z"), .letter("Z"): return GNVT_KEY_Z
        case .letter: return GNVT_KEY_UNIDENTIFIED
        case .function(1): return GNVT_KEY_F1
        case .function(2): return GNVT_KEY_F2
        case .function(3): return GNVT_KEY_F3
        case .function(4): return GNVT_KEY_F4
        case .function(5): return GNVT_KEY_F5
        case .function(6): return GNVT_KEY_F6
        case .function(7): return GNVT_KEY_F7
        case .function(8): return GNVT_KEY_F8
        case .function(9): return GNVT_KEY_F9
        case .function(10): return GNVT_KEY_F10
        case .function(11): return GNVT_KEY_F11
        case .function(12): return GNVT_KEY_F12
        case .function: return GNVT_KEY_UNIDENTIFIED
        }
    }
}

private let ghosttyTerminalWriteCallback: GNVTWriteCallback = { data, len, userdata in
    guard let userdata else {
        return
    }

    let core = Unmanaged<GhosttyTerminalCore>.fromOpaque(userdata).takeUnretainedValue()
    core.handleWriteToPTY(bytes: data, count: len)
}

private extension GNVTCell {
    static var blank: GNVTCell {
        GNVTCell(
            graphemeStart: 0,
            graphemeLength: 0,
            widthRole: 0,
            foreground: GNVTColor(red: 220, green: 224, blue: 232),
            background: GNVTColor(red: 0, green: 0, blue: 0),
            bold: false,
            italic: false,
            inverse: false
        )
    }
}

private extension TerminalCell {
    init(ghosttyCell: GNVTCell, graphemes: [UInt32]) {
        let character = Self.character(from: ghosttyCell, graphemes: graphemes)

        self.init(
            character: character,
            style: TerminalCellStyle(
                foreground: TerminalColor(ghosttyColor: ghosttyCell.foreground),
                background: TerminalColor(ghosttyColor: ghosttyCell.background),
                isBold: ghosttyCell.bold,
                isItalic: ghosttyCell.italic,
                isInverse: ghosttyCell.inverse
            ),
            widthRole: TerminalCellWidthRole(rawValue: ghosttyCell.widthRole) ?? .narrow
        )
    }

    private static func character(from ghosttyCell: GNVTCell, graphemes: [UInt32]) -> String {
        guard ghosttyCell.graphemeLength > 0 else {
            return " "
        }

        let start = ghosttyCell.graphemeStart
        let end = start + Int(ghosttyCell.graphemeLength)
        guard start >= 0, end <= graphemes.count else {
            return " "
        }

        let scalars = graphemes[start..<end].compactMap(UnicodeScalar.init)
        guard !scalars.isEmpty else {
            return " "
        }

        var view = String.UnicodeScalarView()
        for scalar in scalars {
            view.append(scalar)
        }
        return String(view)
    }
}

private extension TerminalColor {
    init(ghosttyColor: GNVTColor) {
        self.init(red: ghosttyColor.red, green: ghosttyColor.green, blue: ghosttyColor.blue)
    }
}
