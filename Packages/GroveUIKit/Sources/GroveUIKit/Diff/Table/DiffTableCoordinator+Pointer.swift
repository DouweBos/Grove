// Diff/Table/DiffTableCoordinator+Pointer.swift
// GroveUIKit
//
// Clicks select lines, a drag along one line selects its text, and the pointer shows what's clickable.

#if os(macOS)
import AppKit
import GroveKit

extension DiffTableCoordinator {

    // MARK: Pointer

    /// Nil leaves the cursor to what's under it, e.g. the app's card.
    func cursor(row: Int, x: CGFloat) -> NSCursor? {
        guard palette.showsPointingHand else { return nil }
        let x = x - geometry.scrolledX
        guard rows.indices.contains(row) else { return .arrow }
        switch rows[row].kind {
        case .annotation:
            return nil
        case .header:
            guard let table, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DiffRowCell<DiffHunkHeaderView>
            else { return .arrow }
            return cell.content.isOverButton(NSPoint(x: x, y: geometry.metrics.headerHeight / 2)) ? .pointingHand : .arrow
        case .line, .pair:
            guard let side = side(row: row, x: x), isOnButton(side, x: x) else { return .arrow }
            return .pointingHand
        }
    }

    func pointerMoved(row: Int, x: CGFloat) {
        if annotations != nil || hover != nil {
            setHover(side(row: row, x: x - geometry.scrolledX).map { (row: row, side: $0) })
        }
        cursor(row: row, x: x)?.set()
    }

    // MARK: Clicks

    /// Option-click opens the line in the app.
    func optionClicked(row: Int) -> Bool {
        guard let openFile = host.openFile, let diff, let line = newLine(at: row) else { return false }
        openFile(diff.filePath, line)
        return true
    }

    /// The new side's line a row shows; a removed line maps to where it was.
    func newLine(at row: Int) -> Int? {
        guard let diff, rows.indices.contains(row) else { return nil }
        let hunk = diff.hunks[rows[row].hunk]
        let index: Int?
        switch rows[row].kind {
        case .header: index = hunk.lines.firstIndex { $0.newLineNumber != nil }
        case .line(let line): index = line
        case .pair(let left, let right): index = right ?? left
        case .annotation: return nil
        }
        guard let index else { return nil }
        if let number = hunk.lines[index].newLineNumber { return number }
        return hunk.lines[..<index].last { $0.newLineNumber != nil }?.newLineNumber.map { $0 + 1 }
            ?? hunk.lines.first { $0.newLineNumber != nil }?.newLineNumber
    }

    // MARK: Text

    /// Where a side's text begins in the document.
    private func textOrigin(_ side: GitDiffLineSide?) -> CGFloat {
        let start = side == .new ? geometry.scrolledX + geometry.half : side == .old ? geometry.scrolledX : 0
        return start + geometry.textX
    }

    /// The code under a document point, if it isn't a gutter or an empty side.
    func codeSide(row: Int, x: CGFloat) -> (side: GitDiffLineSide?, origin: CGFloat)? {
        guard rows.indices.contains(row) else { return nil }
        let onScreen = x - geometry.scrolledX
        switch rows[row].kind {
        case .line:
            return onScreen >= geometry.textX ? (nil, textOrigin(nil)) : nil
        case .pair(let left, let right):
            let isNew = onScreen >= geometry.half
            guard (isNew ? right : left) != nil, onScreen - (isNew ? geometry.half : 0) >= geometry.textX else { return nil }
            let side: GitDiffLineSide = isNew ? .new : .old
            return (side, textOrigin(side))
        case .header, .annotation:
            return nil
        }
    }

    func text(inRow row: Int, side: GitDiffLineSide?) -> DiffLineText? {
        guard let diff, rows.indices.contains(row), let index = rows[row].lineIndices(side).first else { return nil }
        return DiffLineText(diff.hunks[rows[row].hunk].lines[index].content, columns: geometry.wrapColumns)
    }

    func textOffset(in text: DiffLineText, row: Int, origin: CGFloat, point: NSPoint) -> Int {
        guard let table else { return 0 }
        return DiffTextDrawing(metrics: geometry.metrics, palette: palette)
            .offset(in: text, at: NSPoint(x: point.x - origin, y: point.y - table.rect(ofRow: row).minY))
    }

    func selectText(row: Int, side: GitDiffLineSide?, range: NSRange) {
        table?.deselectAll(nil)
        textSelection = range.length > 0 ? DiffTextSelection(row: row, side: side, range: range) : nil
    }

    /// A drag across lines selects them.
    func selectRows(from start: Int, to end: Int) {
        guard let table else { return }
        let range = IndexSet(integersIn: min(start, end)...max(start, end))
        textSelection = nil
        table.selectRowIndexes(range.filteredIndexSet { rows.indices.contains($0) && rows[$0].kind.isSelectable },
                               byExtendingSelection: false)
    }

    /// A click selects the line; on the only selected line, it takes that back.
    func clicked(row: Int) {
        guard let table else { return }
        textSelection = nil
        if table.selectedRowIndexes == IndexSet(integer: row) {
            table.deselectAll(nil)
        } else {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
    }
}
#endif
