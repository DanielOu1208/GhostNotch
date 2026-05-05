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
        var cells = Array(repeating: GNVTCell.blank, count: columns * rows)
        var meta = GNVTSnapshotMeta()

        let success = cells.withUnsafeMutableBufferPointer { buffer in
            GNVTTerminalSnapshot(terminal, buffer.baseAddress, buffer.count, &meta)
        }

        guard success else {
            cachedSnapshot = .empty(columns: columns, rows: rows)
            return
        }

        columns = Int(meta.columns)
        rows = Int(meta.rows)
        cachedSnapshot = TerminalRenderSnapshot(
            columns: columns,
            rows: rows,
            cells: cells.map(TerminalCell.init(ghosttyCell:)),
            cursorColumn: Int(meta.cursorColumn),
            cursorRow: Int(meta.cursorRow),
            cursorVisible: meta.cursorVisible,
            isAlternateScreen: meta.isAlternateScreen
        )
    }

    fileprivate func handleWriteToPTY(bytes: UnsafePointer<UInt8>?, count: Int) {
        guard let bytes, count > 0 else {
            return
        }

        onWriteToPTY?(Data(bytes: bytes, count: count))
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
            codepoint: 0,
            foreground: GNVTColor(red: 220, green: 224, blue: 232),
            background: GNVTColor(red: 0, green: 0, blue: 0),
            bold: false,
            italic: false,
            inverse: false
        )
    }
}

private extension TerminalCell {
    init(ghosttyCell: GNVTCell) {
        let character: String
        if ghosttyCell.codepoint == 0 {
            character = " "
        } else if let scalar = UnicodeScalar(ghosttyCell.codepoint) {
            character = String(Character(scalar))
        } else {
            character = " "
        }

        self.init(
            character: character,
            style: TerminalCellStyle(
                foreground: TerminalColor(ghosttyColor: ghosttyCell.foreground),
                background: TerminalColor(ghosttyColor: ghosttyCell.background),
                isBold: ghosttyCell.bold,
                isItalic: ghosttyCell.italic,
                isInverse: ghosttyCell.inverse
            )
        )
    }
}

private extension TerminalColor {
    init(ghosttyColor: GNVTColor) {
        self.init(red: ghosttyColor.red, green: ghosttyColor.green, blue: ghosttyColor.blue)
    }
}
