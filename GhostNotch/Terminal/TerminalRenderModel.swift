import Foundation

struct TerminalColor: Equatable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let foreground = TerminalColor(red: 220, green: 224, blue: 232)
    static let background = TerminalColor(red: 0, green: 0, blue: 0)
    static let cursor = TerminalColor(red: 245, green: 245, blue: 245)

    static func ansi(index: Int, bright: Bool = false) -> TerminalColor {
        let normal = [
            TerminalColor(red: 69, green: 71, blue: 90),
            TerminalColor(red: 243, green: 139, blue: 168),
            TerminalColor(red: 166, green: 227, blue: 161),
            TerminalColor(red: 249, green: 226, blue: 175),
            TerminalColor(red: 137, green: 180, blue: 250),
            TerminalColor(red: 245, green: 194, blue: 231),
            TerminalColor(red: 148, green: 226, blue: 213),
            TerminalColor(red: 186, green: 194, blue: 222),
        ]
        let brightColors = [
            TerminalColor(red: 88, green: 91, blue: 112),
            TerminalColor(red: 243, green: 139, blue: 168),
            TerminalColor(red: 166, green: 227, blue: 161),
            TerminalColor(red: 249, green: 226, blue: 175),
            TerminalColor(red: 137, green: 180, blue: 250),
            TerminalColor(red: 245, green: 194, blue: 231),
            TerminalColor(red: 148, green: 226, blue: 213),
            TerminalColor(red: 245, green: 245, blue: 245),
        ]

        return (bright ? brightColors : normal)[max(0, min(index, 7))]
    }
}

struct TerminalCellStyle: Equatable {
    var foreground: TerminalColor
    var background: TerminalColor
    var underlineColor: TerminalColor?
    var isBold: Bool
    var isItalic: Bool
    var isFaint: Bool
    var isBlinking: Bool
    var isInverse: Bool
    var isInvisible: Bool
    var isStrikethrough: Bool
    var isOverline: Bool
    var underlineStyle: TerminalUnderlineStyle

    static let `default` = TerminalCellStyle(
        foreground: .foreground,
        background: .background,
        underlineColor: nil,
        isBold: false,
        isItalic: false,
        isFaint: false,
        isBlinking: false,
        isInverse: false,
        isInvisible: false,
        isStrikethrough: false,
        isOverline: false,
        underlineStyle: .none
    )
}

enum TerminalUnderlineStyle: Int32, Equatable {
    case none = 0
    case single = 1
    case double = 2
    case curly = 3
    case dotted = 4
    case dashed = 5
}

struct TerminalCell: Equatable {
    var character: String
    var style: TerminalCellStyle
    var widthRole: TerminalCellWidthRole

    static let blank = TerminalCell(character: " ", style: .default, widthRole: .narrow)
}

enum TerminalCellWidthRole: UInt8, Equatable {
    case narrow = 0
    case wideHead = 1
    case wideSpacerTail = 2
    case wideSpacerHead = 3

    var isSpacer: Bool {
        self == .wideSpacerTail || self == .wideSpacerHead
    }
}

enum TerminalCursorStyle: UInt8, Equatable {
    case bar = 0
    case block = 1
    case underline = 2
    case hollowBlock = 3
}

/// Matches `GNVTSnapshotMeta.dirtyState` from GhosttyVTBridge (`uint8_t`).
enum TerminalRenderDirtyState: UInt8, Equatable {
    case clean = 0
    case partial = 1
    case full = 2

    static func fromBridgeValue(_ value: UInt8) -> TerminalRenderDirtyState {
        switch value {
        case Self.clean.rawValue:
            return .clean
        case Self.partial.rawValue:
            return .partial
        case Self.full.rawValue:
            return .full
        default:
            return .full
        }
    }
}

struct TerminalRenderSnapshot: Equatable {
    let columns: Int
    let rows: Int
    let cells: [TerminalCell]
    let cursorColumn: Int
    let cursorRow: Int
    let cursorVisible: Bool
    let cursorBlinking: Bool
    let cursorStyle: TerminalCursorStyle
    let isAlternateScreen: Bool
    let hasMouseTracking: Bool
    let isBracketedPasteMode: Bool
    let isFocusReportingMode: Bool
    let currentWorkingDirectory: String?
    let totalRows: Int
    let scrollbackRows: Int
    let dirtyState: TerminalRenderDirtyState
    let dirtyRows: Set<Int>

    var needsFullRedraw: Bool {
        dirtyState == .full
    }

    /// Rows that must be repainted, including cursor motion when the VT dirty set omits the previous row.
    func rowsNeedingDisplay(previousCursorRow: Int?) -> Set<Int> {
        if needsFullRedraw {
            return Set(0..<rows)
        }

        var rows = dirtyRows
        guard cursorVisible else {
            return rows
        }

        rows.insert(cursorRow)
        if let previousCursorRow, previousCursorRow >= 0, previousCursorRow < self.rows {
            rows.insert(previousCursorRow)
        }
        return rows
    }

    static func empty(
        columns: Int = 80,
        rows: Int = 18,
        currentWorkingDirectory: String? = nil
    ) -> TerminalRenderSnapshot {
        TerminalRenderSnapshot(
            columns: columns,
            rows: rows,
            cells: Array(repeating: .blank, count: max(columns, 1) * max(rows, 1)),
            cursorColumn: 0,
            cursorRow: 0,
            cursorVisible: true,
            cursorBlinking: false,
            cursorStyle: .bar,
            isAlternateScreen: false,
            hasMouseTracking: false,
            isBracketedPasteMode: false,
            isFocusReportingMode: false,
            currentWorkingDirectory: currentWorkingDirectory,
            totalRows: rows,
            scrollbackRows: 0,
            dirtyState: .full,
            dirtyRows: Set(0..<max(rows, 1))
        )
    }

    static func message(_ text: String, columns: Int = 80, rows: Int = 18) -> TerminalRenderSnapshot {
        let normalizedColumns = max(columns, 2)
        let normalizedRows = max(rows, 1)
        var cells = Array(repeating: TerminalCell.blank, count: normalizedColumns * normalizedRows)
        var row = 0
        var column = 0

        for character in text {
            if character == "\n" {
                row += 1
                column = 0
                if row >= normalizedRows {
                    break
                }
                continue
            }

            guard column < normalizedColumns else {
                row += 1
                column = 0
                if row >= normalizedRows {
                    break
                }
                continue
            }

            cells[row * normalizedColumns + column] = TerminalCell(
                character: String(character),
                style: .default,
                widthRole: .narrow
            )
            column += 1
        }

        return TerminalRenderSnapshot(
            columns: normalizedColumns,
            rows: normalizedRows,
            cells: cells,
            cursorColumn: column,
            cursorRow: row,
            cursorVisible: false,
            cursorBlinking: false,
            cursorStyle: .bar,
            isAlternateScreen: false,
            hasMouseTracking: false,
            isBracketedPasteMode: false,
            isFocusReportingMode: false,
            currentWorkingDirectory: nil,
            totalRows: normalizedRows,
            scrollbackRows: 0,
            dirtyState: .full,
            dirtyRows: Set(0..<normalizedRows)
        )
    }

    func cell(row: Int, column: Int) -> TerminalCell {
        guard row >= 0, row < rows, column >= 0, column < columns else {
            return .blank
        }

        return cells[row * columns + column]
    }

    var plainText: String {
        var lines: [String] = []
        for row in 0..<rows {
            lines.append(textLine(row: row, startColumn: 0, endColumn: columns - 1, trimsRightPadding: true))
        }
        return lines.joined(separator: "\n")
    }

    func text(in selection: TerminalSelection) -> String {
        let normalized = selection.normalized
        var lines: [String] = []

        for row in normalized.start.row...normalized.end.row {
            let startColumn = row == normalized.start.row ? normalized.start.column : 0
            let endColumn = row == normalized.end.row ? normalized.end.column : columns - 1
            guard startColumn <= endColumn else {
                continue
            }

            lines.append(
                textLine(
                    row: row,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    trimsRightPadding: endColumn == columns - 1
                )
            )
        }

        return lines.joined(separator: "\n")
    }

    private func textLine(row: Int, startColumn: Int, endColumn: Int, trimsRightPadding: Bool) -> String {
        var line = ""
        for column in startColumn...endColumn {
            appendVisibleText(from: cell(row: row, column: column), to: &line)
        }

        guard trimsRightPadding else {
            return line
        }

        return line.trimmingRightCellPadding()
    }

    private func appendVisibleText(from cell: TerminalCell, to line: inout String) {
        guard !cell.widthRole.isSpacer else {
            return
        }

        line += cell.character
    }
}

private extension String {
    func trimmingRightCellPadding() -> String {
        var result = self
        while result.last == " " || result.last == "\t" {
            result.removeLast()
        }
        return result
    }
}

struct TerminalGridResize: Equatable {
    let columns: Int
    let rows: Int
    let cellWidthPixels: Int
    let cellHeightPixels: Int

    static func normalized(
        columns: Int,
        rows: Int,
        cellWidthPixels: Int,
        cellHeightPixels: Int
    ) -> TerminalGridResize {
        TerminalGridResize(
            columns: max(columns, 2),
            rows: max(rows, 1),
            cellWidthPixels: max(cellWidthPixels, 1),
            cellHeightPixels: max(cellHeightPixels, 1)
        )
    }
}

struct TerminalScrollEvent: Equatable {
    let deltaRows: Int
    let row: Int
    let column: Int
}

enum TerminalMouseEventAction: UInt8, Equatable {
    case press = 0
    case release = 1
    case motion = 2
}

enum TerminalMouseButton: UInt8, Equatable {
    case unknown = 0
    case left = 1
    case right = 2
    case middle = 3
}

struct TerminalMouseEvent: Equatable {
    let action: TerminalMouseEventAction
    let button: TerminalMouseButton
    let row: Int
    let column: Int
    let modifiers: TerminalKeyModifiers
    let anyButtonPressed: Bool
}

struct TerminalGridPoint: Equatable, Comparable {
    let row: Int
    let column: Int

    static func < (lhs: TerminalGridPoint, rhs: TerminalGridPoint) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

struct TerminalSelection: Equatable {
    let start: TerminalGridPoint
    let end: TerminalGridPoint

    var normalized: TerminalSelection {
        start <= end ? self : TerminalSelection(start: end, end: start)
    }

    func contains(row: Int, column: Int) -> Bool {
        let normalized = normalized
        let point = TerminalGridPoint(row: row, column: column)
        return point >= normalized.start && point <= normalized.end
    }

    func intersects(rows dirtyRows: Set<Int>) -> Bool {
        let normalized = normalized
        return dirtyRows.contains { row in
            row >= normalized.start.row && row <= normalized.end.row
        }
    }

    func isValid(in snapshot: TerminalRenderSnapshot) -> Bool {
        let normalized = normalized
        return normalized.start.row >= 0 &&
            normalized.end.row < snapshot.rows &&
            normalized.start.column >= 0 &&
            normalized.end.column < snapshot.columns
    }
}
