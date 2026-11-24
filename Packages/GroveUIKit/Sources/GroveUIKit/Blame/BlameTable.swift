// Blame/BlameTable.swift
// GroveUIKit
//
// A blamed file as an NSTableView: rows are reused and drawn directly, so a 100k-line file scrolls like a small one.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// The type of Blame's table, for an app's tests and drivers to find it by.
public class GitBlameTableView: NSTableView {}

struct BlameTable: NSViewRepresentable {
    let viewModel: BlameViewModel
    let showInHistory: ((String) -> Void)?
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var uiHost

    func makeCoordinator() -> BlameTableCoordinator { BlameTableCoordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.uiHost = uiHost
        coordinator.showInHistory = showInHistory
        // Reading these here is what makes SwiftUI call us when they change.
        coordinator.update(lines: viewModel.lines, file: viewModel.selectedFile, revision: viewModel.revision, style: style)
    }
}

@MainActor
final class BlameTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let viewModel: BlameViewModel
    var uiHost = GitUIHost.system
    var showInHistory: ((String) -> Void)?
    weak var table: BlameNSTableView?
    private(set) var lines: [BlameLine] = []
    private(set) var drawing: BlameDrawing?
    private var style: GitUIStyle?
    private var document: String?
    private var dates: (oldest: Date, newest: Date) = (.distantPast, .distantPast)
    private var longest = 0

    init(viewModel: BlameViewModel) {
        self.viewModel = viewModel
    }

    func makeView() -> NSScrollView {
        let table = BlameNSTableView()
        table.style = .plain
        table.headerView = nil
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.setAccessibilityLabel("Blame")
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line")))
        table.dataSource = self
        table.delegate = self
        table.coordinator = self
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollResized), name: NSView.frameDidChangeNotification,
                                               object: scroll)
        self.table = table
        return scroll
    }

    func update(lines: [BlameLine], file: String?, revision: String?, style: GitUIStyle) {
        guard let table else { return }
        let linesChanged = lines != self.lines
        let styleChanged = style != self.style
        guard linesChanged || styleChanged else { return }
        if linesChanged {
            self.lines = lines
            var oldest = Date.distantFuture, newest = Date.distantPast, longest = 0
            for line in lines {
                if let date = line.entry?.authorDate {
                    oldest = min(oldest, date)
                    newest = max(newest, date)
                }
                longest = max(longest, line.text.utf8.count)
            }
            dates = (oldest, newest)
            self.longest = longest
        }
        if styleChanged {
            self.style = style
            drawing = BlameDrawing(style)
            table.rowHeight = drawing?.metrics.lineHeight ?? 18
        }
        resizeColumn()
        table.reloadData()
        let key = "\(file ?? "")@\(revision ?? "")"
        if key != document {
            document = key
            table.deselectAll(nil)
            table.scroll(.zero)
        }
    }

    @objc private func scrollResized() { resizeColumn() }

    private func resizeColumn() {
        guard let table, let drawing, let column = table.tableColumns.first else { return }
        let width = max(drawing.metrics.width(longest: longest), table.enclosingScrollView?.contentSize.width ?? 0)
        if abs(column.width - width) > 0.5 { column.width = width }
    }

    /// 1 for the newest commit in the file, 0 for the oldest.
    func age(of line: BlameLine) -> CGFloat {
        guard let date = line.entry?.authorDate else { return 0 }
        let span = dates.newest.timeIntervalSince(dates.oldest)
        return span > 0 ? CGFloat(date.timeIntervalSince(dates.oldest) / span) : 1
    }

    // MARK: Data

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard lines.indices.contains(row), let drawing else { return nil }
        let cell = tableView.makeView(withIdentifier: BlameLineCell.identifier, owner: nil) as? BlameLineCell ?? BlameLineCell()
        cell.configure(lines[row], age: age(of: lines[row]), drawing: drawing)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = BlameRowView()
        if let drawing { view.fill = drawing.palette.selection }
        return view
    }

    // MARK: Events

    /// The commit a gutter click at `x` re-blames before; nil off the gutter or on an uncommitted line.
    func commit(row: Int, x: CGFloat) -> String? {
        guard let drawing, x < drawing.metrics.annotationWidth, lines.indices.contains(row),
              let sha = lines[row].entry?.commitSHA, sha != BlameDrawing.uncommittedSHA else { return nil }
        return sha
    }

    /// A click on a line's commit shows the file as it was before it.
    func blameBefore(_ sha: String) {
        Task { await viewModel.blameBefore(sha) }
    }

    /// Opens a line in the app, only while it's the file as it is now.
    var openLine: ((Int) -> Void)? {
        guard let openFile = uiHost.openFile, viewModel.isAtWorkingTree, let file = viewModel.selectedFile else { return nil }
        return { openFile(file, $0) }
    }

    func optionClicked(row: Int) -> Bool {
        guard let openLine, lines.indices.contains(row) else { return false }
        openLine(lines[row].number)
        return true
    }

    func cursor(row: Int, x: CGFloat) -> NSCursor? {
        guard drawing?.palette.showsPointingHand == true else { return nil }
        return commit(row: row, x: x) == nil ? .arrow : .pointingHand
    }

    func copySelection() {
        guard let table else { return }
        let text = table.selectedRowIndexes.compactMap { lines.indices.contains($0) ? lines[$0].text : nil }
        guard !text.isEmpty else { return }
        uiHost.copy(text.joined(separator: "\n"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if let table { fill(menu, row: table.clickedRow) }
    }

    func fill(_ menu: NSMenu, row: Int) {
        guard lines.indices.contains(row) else { return }
        let line = lines[row]
        let copy = uiHost.copy
        if let openLine {
            menu.addItem(ClosureMenuItem("Open in Editor at Line") { openLine(line.number) })
            menu.addItem(.separator())
        }
        if let sha = line.entry?.commitSHA, sha != BlameDrawing.uncommittedSHA {
            menu.addItem(ClosureMenuItem("Blame Before \(sha.prefix(7))") { [weak self] in self?.blameBefore(sha) })
            if let showInHistory {
                menu.addItem(ClosureMenuItem("Show Commit in History") { showInHistory(sha) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Copy SHA") { copy(sha) })
        }
        menu.addItem(ClosureMenuItem("Copy Line") { copy(line.text) })
    }
}

/// Sends gutter clicks and ⌥-clicks to the coordinator; the rest select lines as a table does.
final class BlameNSTableView: GitBlameTableView {
    weak var coordinator: BlameTableCoordinator?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, let coordinator else { return super.mouseDown(with: event) }
        if event.modifierFlags.contains(.option), coordinator.optionClicked(row: row) { return }
        if let sha = coordinator.commit(row: row, x: point.x) { return coordinator.blameBefore(sha) }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.cursor(row: row(at: point), x: point.x)?.set()
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(copy(_:)) ? !selectedRowIndexes.isEmpty : super.validateUserInterfaceItem(item)
    }
}
#endif
