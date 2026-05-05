import Foundation

final class GhosttyTerminalCore {
    var onWriteToPTY: ((Data) -> Void)?

    private(set) var columns: Int
    private(set) var rows: Int

    private var primaryCells: [TerminalCell]
    private var alternateCells: [TerminalCell]
    private var cursorColumn = 0
    private var cursorRow = 0
    private var savedCursorColumn = 0
    private var savedCursorRow = 0
    private var cursorVisible = true
    private var activeStyle = TerminalCellStyle.default
    private var isAlternateScreen = false
    private var parserState = ParserState.normal

    init(columns: Int = 80, rows: Int = 18) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        primaryCells = Array(repeating: .blank, count: self.columns * self.rows)
        alternateCells = Array(repeating: .blank, count: self.columns * self.rows)
    }

    var snapshot: TerminalRenderSnapshot {
        TerminalRenderSnapshot(
            columns: columns,
            rows: rows,
            cells: activeCells,
            cursorColumn: cursorColumn,
            cursorRow: cursorRow,
            cursorVisible: cursorVisible,
            isAlternateScreen: isAlternateScreen
        )
    }

    func processOutput(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)

        for scalar in text.unicodeScalars {
            process(scalar)
        }
    }

    func resize(columns newColumns: Int, rows newRows: Int) {
        let nextColumns = max(newColumns, 2)
        let nextRows = max(newRows, 1)
        guard nextColumns != columns || nextRows != rows else {
            return
        }

        primaryCells = resized(cells: primaryCells, columns: nextColumns, rows: nextRows)
        alternateCells = resized(cells: alternateCells, columns: nextColumns, rows: nextRows)
        columns = nextColumns
        rows = nextRows
        cursorColumn = min(cursorColumn, columns - 1)
        cursorRow = min(cursorRow, rows - 1)
    }

    func focusData() -> Data {
        Data("\u{1B}[I".utf8)
    }

    func blurData() -> Data {
        Data("\u{1B}[O".utf8)
    }

    static func encodePaste(_ text: String, bracketed: Bool = true) -> Data? {
        guard !text.isEmpty else {
            return nil
        }

        var sanitized = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x00, 0x1B, 0x7F:
                sanitized.append(" ")
            case 0x0A:
                sanitized.append(bracketed ? "\n" : "\r")
            default:
                sanitized.unicodeScalars.append(scalar)
            }
        }

        if bracketed {
            return Data(("\u{1B}[200~" + sanitized + "\u{1B}[201~").utf8)
        }

        return Data(sanitized.utf8)
    }

    private var activeCells: [TerminalCell] {
        get { isAlternateScreen ? alternateCells : primaryCells }
        set {
            if isAlternateScreen {
                alternateCells = newValue
            } else {
                primaryCells = newValue
            }
        }
    }

    private func process(_ scalar: UnicodeScalar) {
        switch parserState {
        case .normal:
            processNormal(scalar)
        case .escape:
            processEscape(scalar)
        case .csi(let buffer):
            processCSI(scalar, buffer: buffer)
        case .osc:
            processOSC(scalar)
        }
    }

    private func processNormal(_ scalar: UnicodeScalar) {
        switch scalar.value {
        case 0x1B:
            parserState = .escape
        case 0x0D:
            cursorColumn = 0
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
        case 0x08:
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            let spaces = max(1, 8 - (cursorColumn % 8))
            for _ in 0..<spaces {
                write(" ")
            }
        case 0x07:
            break
        default:
            guard scalar.value >= 0x20 else {
                return
            }
            write(String(scalar))
        }
    }

    private func processEscape(_ scalar: UnicodeScalar) {
        switch scalar {
        case "[":
            parserState = .csi("")
        case "]":
            parserState = .osc
        case "7":
            savedCursorColumn = cursorColumn
            savedCursorRow = cursorRow
            parserState = .normal
        case "8":
            cursorColumn = min(savedCursorColumn, columns - 1)
            cursorRow = min(savedCursorRow, rows - 1)
            parserState = .normal
        case "c":
            reset()
            parserState = .normal
        default:
            parserState = .normal
        }
    }

    private func processCSI(_ scalar: UnicodeScalar, buffer: String) {
        guard scalar.value >= 0x40, scalar.value <= 0x7E else {
            parserState = .csi(buffer + String(scalar))
            return
        }

        handleCSI(buffer: buffer, final: Character(String(scalar)))
        parserState = .normal
    }

    private func processOSC(_ scalar: UnicodeScalar) {
        if scalar.value == 0x07 {
            parserState = .normal
        } else if scalar.value == 0x1B {
            parserState = .escape
        }
    }

    private func handleCSI(buffer: String, final: Character) {
        let isPrivate = buffer.hasPrefix("?")
        let normalized = buffer
            .trimmingCharacters(in: CharacterSet(charactersIn: "?=>"))
        let params = parseParams(normalized)

        switch final {
        case "m":
            applySGR(params)
        case "H", "f":
            let row = (params.first ?? 1) - 1
            let column = (params.dropFirst().first ?? 1) - 1
            moveCursor(row: row, column: column)
        case "A":
            cursorRow = max(0, cursorRow - (params.first ?? 1))
        case "B":
            cursorRow = min(rows - 1, cursorRow + (params.first ?? 1))
        case "C":
            cursorColumn = min(columns - 1, cursorColumn + (params.first ?? 1))
        case "D":
            cursorColumn = max(0, cursorColumn - (params.first ?? 1))
        case "G":
            cursorColumn = min(max((params.first ?? 1) - 1, 0), columns - 1)
        case "d":
            cursorRow = min(max((params.first ?? 1) - 1, 0), rows - 1)
        case "J":
            clearScreen(mode: params.first ?? 0)
        case "K":
            clearLine(mode: params.first ?? 0)
        case "h":
            if isPrivate {
                setPrivateModes(params, enabled: true)
            }
        case "l":
            if isPrivate {
                setPrivateModes(params, enabled: false)
            }
        case "c":
            onWriteToPTY?(Data("\u{1B}[?62;c".utf8))
        case "n":
            if params.first == 6 {
                let response = "\u{1B}[\(cursorRow + 1);\(cursorColumn + 1)R"
                onWriteToPTY?(Data(response.utf8))
            }
        default:
            break
        }
    }

    private func parseParams(_ buffer: String) -> [Int] {
        guard !buffer.isEmpty else {
            return []
        }

        return buffer.split(separator: ";", omittingEmptySubsequences: false).map { part in
            Int(part) ?? 0
        }
    }

    private func applySGR(_ params: [Int]) {
        let codes = params.isEmpty ? [0] : params
        var index = 0

        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                activeStyle = .default
            case 1:
                activeStyle.isBold = true
            case 3:
                activeStyle.isItalic = true
            case 7:
                activeStyle.isInverse = true
            case 22:
                activeStyle.isBold = false
            case 23:
                activeStyle.isItalic = false
            case 27:
                activeStyle.isInverse = false
            case 30...37:
                activeStyle.foreground = .ansi(index: code - 30)
            case 39:
                activeStyle.foreground = .foreground
            case 40...47:
                activeStyle.background = .ansi(index: code - 40)
            case 49:
                activeStyle.background = .background
            case 90...97:
                activeStyle.foreground = .ansi(index: code - 90, bright: true)
            case 100...107:
                activeStyle.background = .ansi(index: code - 100, bright: true)
            case 38, 48:
                index = applyExtendedColor(codes, from: index)
            default:
                break
            }

            index += 1
        }
    }

    private func applyExtendedColor(_ codes: [Int], from index: Int) -> Int {
        guard index + 2 < codes.count else {
            return index
        }

        let isForeground = codes[index] == 38
        let mode = codes[index + 1]

        if mode == 2, index + 4 < codes.count {
            let color = TerminalColor(
                red: UInt8(clamping: codes[index + 2]),
                green: UInt8(clamping: codes[index + 3]),
                blue: UInt8(clamping: codes[index + 4])
            )
            if isForeground {
                activeStyle.foreground = color
            } else {
                activeStyle.background = color
            }
            return index + 4
        }

        if mode == 5, index + 2 < codes.count {
            let color = TerminalColor.ansi(index: codes[index + 2] % 8, bright: codes[index + 2] >= 8)
            if isForeground {
                activeStyle.foreground = color
            } else {
                activeStyle.background = color
            }
            return index + 2
        }

        return index
    }

    private func setPrivateModes(_ modes: [Int], enabled: Bool) {
        for mode in modes {
            switch mode {
            case 25:
                cursorVisible = enabled
            case 47, 1047, 1049:
                useAlternateScreen(enabled)
            default:
                break
            }
        }
    }

    private func useAlternateScreen(_ enabled: Bool) {
        guard isAlternateScreen != enabled else {
            return
        }

        isAlternateScreen = enabled
        cursorColumn = 0
        cursorRow = 0
        if enabled {
            alternateCells = Array(repeating: .blank, count: columns * rows)
        }
    }

    private func write(_ character: String) {
        if cursorColumn >= columns {
            cursorColumn = 0
            lineFeed()
        }

        var cells = activeCells
        cells[cursorRow * columns + cursorColumn] = TerminalCell(character: character, style: activeStyle)
        activeCells = cells
        cursorColumn += 1
    }

    private func lineFeed() {
        if cursorRow == rows - 1 {
            scrollUp()
        } else {
            cursorRow += 1
        }
    }

    private func scrollUp() {
        var cells = activeCells
        cells.removeFirst(columns)
        cells.append(contentsOf: Array(repeating: .blank, count: columns))
        activeCells = cells
    }

    private func moveCursor(row: Int, column: Int) {
        cursorRow = min(max(row, 0), rows - 1)
        cursorColumn = min(max(column, 0), columns - 1)
    }

    private func clearScreen(mode: Int) {
        var cells = activeCells
        switch mode {
        case 0:
            clearCells(&cells, from: cursorRow * columns + cursorColumn, through: cells.count - 1)
        case 1:
            clearCells(&cells, from: 0, through: cursorRow * columns + cursorColumn)
        case 2, 3:
            cells = Array(repeating: .blank, count: columns * rows)
        default:
            break
        }
        activeCells = cells
    }

    private func clearLine(mode: Int) {
        var cells = activeCells
        let rowStart = cursorRow * columns
        switch mode {
        case 0:
            clearCells(&cells, from: rowStart + cursorColumn, through: rowStart + columns - 1)
        case 1:
            clearCells(&cells, from: rowStart, through: rowStart + cursorColumn)
        case 2:
            clearCells(&cells, from: rowStart, through: rowStart + columns - 1)
        default:
            break
        }
        activeCells = cells
    }

    private func clearCells(_ cells: inout [TerminalCell], from start: Int, through end: Int) {
        guard !cells.isEmpty else {
            return
        }

        let lower = max(0, min(start, cells.count - 1))
        let upper = max(0, min(end, cells.count - 1))
        guard lower <= upper else {
            return
        }

        for index in lower...upper {
            cells[index] = .blank
        }
    }

    private func reset() {
        primaryCells = Array(repeating: .blank, count: columns * rows)
        alternateCells = Array(repeating: .blank, count: columns * rows)
        cursorColumn = 0
        cursorRow = 0
        activeStyle = .default
        isAlternateScreen = false
        cursorVisible = true
    }

    private func resized(cells: [TerminalCell], columns newColumns: Int, rows newRows: Int) -> [TerminalCell] {
        var next = Array(repeating: TerminalCell.blank, count: newColumns * newRows)
        let copiedRows = min(rows, newRows)
        let copiedColumns = min(columns, newColumns)

        for row in 0..<copiedRows {
            for column in 0..<copiedColumns {
                next[row * newColumns + column] = cells[row * columns + column]
            }
        }

        return next
    }
}

private enum ParserState {
    case normal
    case escape
    case csi(String)
    case osc
}
