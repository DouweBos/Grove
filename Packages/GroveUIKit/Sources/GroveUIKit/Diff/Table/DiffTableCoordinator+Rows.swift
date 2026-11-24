// Diff/Table/DiffTableCoordinator+Rows.swift
// GroveUIKit

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

extension DiffTableCoordinator: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows.indices.contains(row) && rows[row].kind.isSelectable
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }

    // MARK: Heights

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return geometry.metrics.lineHeight }
        switch rows[row].kind {
        case .header:
            return geometry.metrics.headerHeight
        case .annotation(let index):
            guard let item = annotation(index) else { return 1 }
            return max(1, item.height(cardWidth(for: item)))
        case .line, .pair:
            guard let columns = geometry.wrapColumns, let diff else { return geometry.metrics.lineHeight }
            let item = rows[row]
            let first = heights.measuredThisTurn == 0
            let count = heights.lineCount(
                row: row,
                measure: { Self.lineCount(item, in: diff, columns: columns, measure: DiffWrap.lineCount) },
                estimate: { Self.lineCount(item, in: diff, columns: columns, measure: DiffWrap.estimatedLineCount) })
            if first, heights.measuredThisTurn > 0 {
                DispatchQueue.main.async { [weak self] in self?.heights.startTurn() }
            }
            return CGFloat(count) * geometry.metrics.lineHeight
        }
    }

    private static func lineCount(_ row: DiffRow, in diff: DiffResult, columns: Int, measure: (String, Int) -> Int) -> Int {
        let hunk = row.hunk
        switch row.kind {
        case .line(let index):
            return measure(diff.hunks[hunk].lines[index].content, columns)
        case .pair(let left, let right):
            let old = left.map { measure(diff.hunks[hunk].lines[$0].content, columns) } ?? 1
            guard right != left, let right else { return old }
            return max(old, measure(diff.hunks[hunk].lines[right].content, columns))
        case .header, .annotation:
            return 1
        }
    }

    private func correctHeightIfEstimated(row: Int) {
        guard let diff, let columns = geometry.wrapColumns else { return }
        let item = rows[row]
        let schedules = heights.corrected.isEmpty
        let wasEstimated = heights.willShow(row: row) {
            Self.lineCount(item, in: diff, columns: columns, measure: DiffWrap.lineCount)
        }
        // Not while the table is in the middle of asking for this row's view.
        guard wasEstimated, schedules else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let table else { return }
            let rows = heights.takeCorrected().filteredIndexSet { $0 < table.numberOfRows }
            withoutAnimation { table.noteHeightOfRows(withIndexesChanged: rows) }
            contentResized()
        }
    }

    // MARK: Views

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if let view = tableView.makeView(withIdentifier: DiffCellID.row, owner: nil) as? DiffRowView { return view }
        let view = DiffRowView()
        view.identifier = DiffCellID.row
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard diff != nil, rows.indices.contains(row) else { return nil }
        switch rows[row].kind {
        case .header:
            let cell = tableView.makeView(withIdentifier: DiffCellID.header, owner: nil) as? DiffHeaderCell
                ?? DiffHeaderCell()
            configure(cell, row: row)
            return cell
        case .annotation:
            let cell = tableView.makeView(withIdentifier: DiffCellID.annotation, owner: nil) as? DiffAnnotationCell
                ?? DiffAnnotationCell()
            configure(cell, row: row)
            return cell
        case .line, .pair:
            correctHeightIfEstimated(row: row)
            let cell = tableView.makeView(withIdentifier: DiffCellID.line, owner: nil) as? DiffLineCell
                ?? DiffLineCell()
            configure(cell, row: row)
            return cell
        }
    }

    func configure(_ view: NSView, row: Int) {
        guard let diff, rows.indices.contains(row) else { return }
        let item = rows[row]
        if let cell = view as? DiffLineCell {
            guard item.kind.isSelectable else { return }
            cell.content.configure(lineContent(item, in: diff), palette: palette)
            cell.content.isSelected = table?.selectedRowIndexes.contains(row) ?? false
            cell.content.textSelection = textSelection?.row == row ? textSelection : nil
            cell.content.hover = hover?.row == row ? hover?.side : nil
            cell.place(geometry, width: geometry.lineWidth)
        } else if let cell = view as? DiffHeaderCell {
            guard item.kind == .header else { return }
            let hunk = diff.hunks[item.hunk]
            let id = hunk.id
            cell.content.configure(
                header: hunk.header, buttons: headerButtons(hunk: item.hunk), palette: palette, metrics: geometry.metrics,
                perform: { [weak self] action in self?.perform(action, hunk: item.hunk, id: id) })
            cell.place(geometry, width: geometry.viewport)
        } else if let cell = view as? DiffAnnotationCell {
            guard case .annotation(let index) = item.kind, let annotation = annotation(index) else { return }
            let id = annotation.id
            let context = GitDiffAnnotationContext(width: cardWidth(for: annotation)) { [weak self] content in
                self?.presentPopover(content, overAnnotation: id)
            }
            cell.content.configure(annotation.content(context), inset: cardInset(for: annotation), style: style)
            cell.place(geometry, width: geometry.viewport)
        }
    }

    private func lineContent(_ row: DiffRow, in diff: DiffResult) -> DiffLineContent {
        let lines = diff.hunks[row.hunk].lines
        let columns = geometry.wrapColumns
        func side(_ index: Int) -> DiffLineContent.Side {
            let text = DiffLineText(lines[index].content, spans: highlights.syntax(hunk: row.hunk, line: index),
                                    words: highlights.changedWords(hunk: row.hunk, line: index), columns: columns)
            return DiffLineContent.Side(line: lines[index], text: text)
        }
        switch row.kind {
        case .line(let index):
            return DiffLineContent(row: row, first: side(index), second: nil)
        case .pair(let left, let right):
            let old = left.map(side)
            return DiffLineContent(row: row, first: old, second: left == right ? old : right.map(side))
        case .header, .annotation:
            return DiffLineContent(row: row, first: nil, second: nil)
        }
    }

    // MARK: Redrawing what's on screen

    func forEachVisibleCell(_ body: (_ cell: NSView, _ row: Int) -> Void) {
        table?.enumerateAvailableRowViews { rowView, row in
            guard rows.indices.contains(row), rowView.numberOfColumns > 0,
                  let cell = rowView.view(atColumn: 0) as? NSView else { return }
            body(cell, row)
        }
    }

    func configureVisible() {
        forEachVisibleCell(configure)
    }

    func placeVisible() {
        forEachVisibleCell { cell, _ in
            if let cell = cell as? DiffLineCell {
                cell.place(geometry, width: geometry.lineWidth)
            } else if let cell = cell as? DiffHeaderCell {
                cell.place(geometry, width: geometry.viewport)
            } else if let cell = cell as? DiffAnnotationCell {
                cell.place(geometry, width: geometry.viewport)
            }
        }
    }

    func highlightsArrived(in hunks: Set<Int>) {
        forEachVisibleCell { cell, row in
            if hunks.contains(rows[row].hunk), cell is DiffLineCell { configure(cell, row: row) }
        }
    }

    func withoutAnimation(_ body: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        body()
        NSAnimationContext.endGrouping()
    }
}
#endif
