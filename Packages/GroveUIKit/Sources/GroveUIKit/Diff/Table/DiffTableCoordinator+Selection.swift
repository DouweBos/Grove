// Diff/Table/DiffTableCoordinator+Selection.swift
// GroveUIKit
//
// Selected lines narrow their hunk's actions to them, and copy as the file's text.

#if os(macOS)
import AppKit
import GroveKit

extension DiffTableCoordinator {

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table else { return }
        if !table.selectedRowIndexes.isEmpty { textSelection = nil }
        showSelection()
    }

    /// Selected rows and text, and the headers that re-label "Hunk" as "Lines" with them.
    func showSelection() {
        guard let table else { return }
        let selected = table.selectedRowIndexes
        forEachVisibleCell { cell, row in
            if let cell = cell as? DiffRowCell<DiffLineView> {
                cell.content.isSelected = selected.contains(row)
                cell.content.textSelection = textSelection?.row == row ? textSelection : nil
            } else if let cell = cell as? DiffRowCell<DiffHunkHeaderView>, rows[row].kind == .header {
                cell.content.setButtons(headerButtons(hunk: rows[row].hunk))
            }
        }
    }

    private func rowRange(ofHunk index: Int) -> Range<Int>? {
        guard hunkStarts.indices.contains(index) else { return nil }
        return hunkStarts[index]..<(index + 1 < hunkStarts.count ? hunkStarts[index + 1] : rows.count)
    }

    private func selectedRows(inHunk index: Int) -> IndexSet {
        guard let table, let range = rowRange(ofHunk: index), !table.selectedRowIndexes.isEmpty else { return IndexSet() }
        return table.selectedRowIndexes.intersection(IndexSet(integersIn: range))
    }

    func hasSelectedChanges(inHunk index: Int) -> Bool {
        guard let diff, diff.hunks.indices.contains(index) else { return false }
        let lines = diff.hunks[index].lines
        return selectedRows(inHunk: index).contains { row in
            rows[row].lineIndices().contains { lines[$0].type != .context }
        }
    }

    /// The selected change lines in a hunk; empty means the whole hunk.
    func selectedLines(inHunk index: Int) -> [DiffLine] {
        guard let diff, diff.hunks.indices.contains(index) else { return [] }
        let lines = diff.hunks[index].lines
        var picked = IndexSet()
        for row in selectedRows(inHunk: index) {
            for line in rows[row].lineIndices() { picked.insert(line) }
        }
        return picked.map { lines[$0] }.filter { $0.type != .context }
    }

    // MARK: Actions

    func headerButtons(hunk index: Int) -> [DiffHunkButton] {
        guard staging != nil else { return [] }
        return hasSelectedChanges(inHunk: index) ? lineButtons : hunkButtons
    }

    var lineButtons: [DiffHunkButton] {
        switch staging?.side {
        case .unstaged:
            [DiffHunkButton(title: "Discard Lines", action: .discardLines), DiffHunkButton(title: "Stage Lines", action: .stageLines)]
        case .staged:
            [DiffHunkButton(title: "Unstage Lines", action: .unstageLines)]
        case nil:
            []
        }
    }

    var hunkButtons: [DiffHunkButton] {
        switch staging?.side {
        case .unstaged:
            [DiffHunkButton(title: "Discard Hunk", action: .discardHunk), DiffHunkButton(title: "Stage Hunk", action: .stageHunk)]
        case .staged:
            [DiffHunkButton(title: "Unstage Hunk", action: .unstageHunk)]
        case nil:
            []
        }
    }

    /// A button or menu item can outlive its diff, so it names the hunk it was made for.
    func perform(_ action: HunkAction, hunk index: Int, id: String) {
        guard let diff, let staging, diff.hunks.indices.contains(index), diff.hunks[index].id == id else { return }
        let lines: [DiffLine]
        switch action {
        case .stageHunk, .unstageHunk, .discardHunk:
            lines = []
        case .stageLines, .unstageLines, .discardLines:
            lines = selectedLines(inHunk: index)
            // No lines would mean the whole hunk.
            guard !lines.isEmpty else { return }
        }
        staging.perform(action, diff.hunks[index], lines)
        table?.deselectAll(nil)
    }

    // MARK: Across updates

    /// Where the selected lines are in `next`: only hunks that are exactly as they were keep theirs.
    func selectedLines(movedTo next: DiffResult) -> [Int: IndexSet] {
        guard let diff, let table, !table.selectedRowIndexes.isEmpty else { return [:] }
        let indices = Dictionary(next.hunks.indices.map { (next.hunks[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        var moved: [Int: Int?] = [:]
        var kept: [Int: IndexSet] = [:]
        for row in table.selectedRowIndexes where rows.indices.contains(row) && rows[row].kind.isSelectable {
            let hunk = rows[row].hunk
            if moved[hunk] == nil {
                let found = indices[diff.hunks[hunk].id].flatMap { next.hunks[$0] == diff.hunks[hunk] ? $0 : nil }
                moved.updateValue(found, forKey: hunk)
            }
            guard let target = moved[hunk] ?? nil else { continue }
            for line in rows[row].lineIndices() { kept[target, default: IndexSet()].insert(line) }
        }
        return kept
    }

    func rowsShowing(_ lines: [Int: IndexSet]) -> IndexSet {
        var selected = IndexSet()
        for hunk in lines.keys {
            guard let range = rowRange(ofHunk: hunk), let wanted = lines[hunk] else { continue }
            for row in range where rows[row].lineIndices().contains(where: wanted.contains) { selected.insert(row) }
        }
        return selected
    }

    // MARK: Copy

    /// The text selected in a line, or the selected lines.
    func copySelection() -> String {
        guard let diff, let table else { return "" }
        if let textSelection, let text = text(inRow: textSelection.row, side: textSelection.side) {
            return text.original(textSelection.range)
        }
        return table.selectedRowIndexes.compactMap { row -> String? in
            guard rows.indices.contains(row) else { return nil }
            let lines = diff.hunks[rows[row].hunk].lines
            switch rows[row].kind {
            case .header, .annotation: return nil
            case .line(let index): return lines[index].content
            case .pair(let left, let right): return (right ?? left).map { lines[$0].content }
            }
        }.joined(separator: "\n")
    }

    func copyToHost() {
        let text = copySelection()
        guard !text.isEmpty else { return }
        host.copy(text)
        host.toast("Copied")
    }
}
#endif
