// History/List/CommitTable.swift
// GroveUIKit
//
// The commit list as an NSTableView: rows are reused and drawn directly, so a 100k-commit history scrolls like
// a small one. Selection, keys and paging all go through the HistoryViewModel; the table only mirrors it.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// The type of History's commit table, for an app's tests and drivers to find it by.
public class GitCommitTableView: NSTableView {}

struct CommitTable: NSViewRepresentable {
    let viewModel: HistoryViewModel
    let actions: CommitActions
    @Environment(\.gitStyle) private var style
    @Environment(\.historyHost) private var host

    func makeCoordinator() -> CommitTableCoordinator { CommitTableCoordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.actions = actions
        // Reading these here is what makes SwiftUI call us when they change.
        coordinator.update(CommitTableInput(
            commits: viewModel.filteredCommits, layout: viewModel.layout,
            showsGraph: viewModel.layout == .graph && !viewModel.isFiltering, graphColumns: viewModel.maxGraphColumns,
            refsKey: refsKey, selection: viewModel.selection.rows, focus: viewModel.selectedCommit?.id, style: style,
            ownCommits: host.ownCommits, avatarURL: host.avatarURL))
    }

    /// Changes whenever a row's decoration would: a ref or HEAD moving, the graph rebuilding, sync state arriving.
    private var refsKey: Int {
        var hasher = Hasher()
        for branch in viewModel.branches { hasher.combine(branch.id); hasher.combine(branch.targetSHA) }
        for tag in viewModel.tags { hasher.combine(tag.id); hasher.combine(tag.targetSHA) }
        hasher.combine(viewModel.headSHA)
        hasher.combine(viewModel.graphNodes.count)
        if let first = viewModel.commits.first { hasher.combine(viewModel.syncState(of: first)) }
        return hasher.finalize()
    }
}

/// What one update of the table shows.
struct CommitTableInput {
    var commits: [CommitInfo]
    var layout: HistoryLayout
    var showsGraph: Bool
    var graphColumns: Int
    var refsKey: Int
    var selection: Set<String>
    var focus: String?
    var style: GitUIStyle
    var ownCommits: Set<String>?
    var avatarURL: ((String, Int) -> URL?)?
}

@MainActor
final class CommitTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let viewModel: HistoryViewModel
    var actions: CommitActions?
    weak var table: CommitNSTableView?
    private(set) var commits: [CommitInfo] = []
    private(set) var rows = CommitListRows()
    /// Built only once a lookup isn't near the top or the last focus.
    private var indexByID: [String: Int]?
    private var lastFocusIndex = 0
    private var input: CommitTableInput?
    private var drawing: CommitDrawing?
    private var dataKey: [AnyHashable] = []
    private var appliedSelection: Set<String> = []
    private var appliedFocus: String?
    private var grouping: Task<Void, Never>?
    private let avatars = AvatarImages()
    private let symbols = SymbolImages()

    init(viewModel: HistoryViewModel) {
        self.viewModel = viewModel
        super.init()
        avatars.onLoad = { [weak self] email in self?.redraw(email: email) }
    }

    func makeView() -> NSScrollView {
        let table = CommitNSTableView()
        table.style = .plain
        table.headerView = nil
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.floatsGroupRows = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Commits")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.coordinator = self
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        table.autoresizingMask = [.width]
        self.table = table
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewResized),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    func update(_ input: CommitTableInput) {
        guard let table else { return }
        let key: [AnyHashable] = [
            input.commits.count, input.commits.first?.id, input.commits.last?.id, input.layout, input.showsGraph,
            input.graphColumns, input.refsKey, input.ownCommits?.count, input.avatarURL == nil,
        ]
        let styleChanged = input.style != self.input?.style
        let grouped = input.layout == .graph
        self.input = input
        if key != dataKey || styleChanged {
            if key != dataKey {
                commits = input.commits
                indexByID = nil
                grouping?.cancel()
                if grouped, commits.count > Self.groupsInBackgroundAbove {
                    rows = CommitListRows(commits, grouped: false)
                    groupInBackground()
                } else {
                    rows = CommitListRows(commits, grouped: grouped)
                }
            }
            dataKey = key
            drawing = CommitDrawing(palette: CommitListPalette(input.style), metrics: CommitListMetrics(input.style),
                                    symbols: symbols)
            table.reloadData()
            appliedSelection = []
        }
        if input.selection != appliedSelection {
            appliedSelection = input.selection
            let indexes = IndexSet(input.selection.compactMap { index(of: $0).map { rows.row(ofCommit: $0) } })
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }
        if input.focus != appliedFocus {
            appliedFocus = input.focus
            if let focus = input.focus, let index = index(of: focus) {
                lastFocusIndex = index
                pendingReveal = focus
                revealPending()
            }
        }
    }

    /// The focus waiting for the table to get a height; before its first layout any row would scroll to the top.
    private var pendingReveal: String?

    func revealPending() {
        guard let table, let focus = pendingReveal, table.visibleRect.height > 0 else { return }
        pendingReveal = nil
        guard let index = index(of: focus) else { return }
        let row = rows.row(ofCommit: index)
        // A day's first commit brings its header along, so its date stays in sight.
        if row > 0, case .day = rows.row(row - 1) { table.scrollRowToVisible(row - 1) }
        table.scrollRowToVisible(row)
    }

    @objc private func clipViewResized() { revealPending() }

    /// A long history shows at once and gets its day headers a moment later, rather than stall its first layout.
    static let groupsInBackgroundAbove = 20_000

    private func groupInBackground() {
        let snapshot = commits
        grouping = Task { [weak self] in
            let groups = await Task.detached(priority: .userInitiated) { CommitListRows.groups(snapshot) }.value
            guard let self, !Task.isCancelled, let table, self.commits.count == snapshot.count,
                  self.commits.first?.id == snapshot.first?.id else { return }
            let top = rows.commitIndex(atRow: table.rows(in: table.visibleRect).location)
            rows = CommitListRows(groups: groups, commitCount: snapshot.count)
            table.reloadData()
            appliedSelection = []
            if let input { update(input) }
            if let top { table.scroll(table.rect(ofRow: top == 0 ? 0 : rows.row(ofCommit: top)).origin) }
        }
    }

    /// Arrow keys move the focus by a row and a selection starts near the top, so most lookups never need the map.
    private func index(of id: String) -> Int? {
        if let indexByID { return indexByID[id] }
        let near = max(0, lastFocusIndex - 64)..<min(commits.count, lastFocusIndex + 64)
        let top = 0..<min(commits.count, 512)
        for range in [near, top] {
            if let found = commits[range].firstIndex(where: { $0.id == id }) { return found }
        }
        var map = [String: Int](minimumCapacity: commits.count)
        for (index, commit) in commits.enumerated() where map[commit.id] == nil { map[commit.id] = index }
        indexByID = map
        return map[id]
    }

    // MARK: Data

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let input, let drawing else { return 26 }
        if case .day = rows.row(row) { return drawing.metrics.dayHeight }
        return drawing.metrics.rowHeight(input.layout)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let input, let drawing, row >= 0, row < rows.count else { return nil }
        let cell = tableView.makeView(withIdentifier: CommitRowCell.identifier, owner: nil) as? CommitRowCell ?? CommitRowCell()
        switch rows.row(row) {
        case .day(let date, let first):
            let lanes = viewModel.graphNodes[commits[first].id]?.lanesAbove ?? []
            cell.configure(.day(date, lanes: lanes, graphColumns: input.graphColumns, showsGraph: input.showsGraph),
                           layout: input.layout, drawing: drawing)
        case .commit(let index):
            let commit = commits[index]
            if index == commits.count - 1 { viewModel.rowAppeared(commit) }
            cell.configure(.commit(model(for: commit, input)), layout: input.layout, drawing: drawing)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = CommitTableRowView()
        if let input {
            let scale = input.style.fontScale
            view.fill = NSColor(input.style.selectionFill)
            view.radius = input.layout == .graph ? GitMetrics.Radius.row : GitMetrics.Radius.tile
            view.inset = NSSize(width: 4 * scale, height: input.layout == .graph ? 1 : 0)
        }
        return view
    }

    // The view model owns the selection; the table only mirrors it.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        // Dropping the SHA on the working copy cherry-picks it.
        rows.commitIndex(atRow: row).map { commits[$0].id as NSString }
    }

    private func model(for commit: CommitInfo, _ input: CommitTableInput) -> CommitRowModel {
        let head = viewModel.headSHA
        var refs = CommitDisplayRef.display(branches: viewModel.branches(at: commit), tags: viewModel.tags(at: commit))
        // A detached HEAD has no branch to say where it is.
        if commit.id == head, viewModel.filterBranch == nil, !refs.contains(where: { $0.kind == .local(isHEAD: true) }),
           viewModel.headBranchName == nil {
            refs.insert(CommitDisplayRef(id: "HEAD", name: "HEAD", fullName: "HEAD (detached)", kind: .local(isHEAD: true),
                                         isOnRemote: false), at: 0)
        }
        let pixels = Int((drawing?.metrics.avatar ?? 28) * 2)
        let avatar = input.layout == .graph ? avatars.image(email: commit.authorEmail,
                                                            url: input.avatarURL?(commit.authorEmail, pixels)) : nil
        return CommitRowModel(
            commit: commit, node: input.showsGraph ? viewModel.graphNodes[commit.id] : nil, graphColumns: input.graphColumns,
            refs: refs, sync: viewModel.syncState(of: commit), isHead: commit.id == head,
            isDimmed: input.ownCommits.map { !$0.contains(commit.id) } ?? false, avatar: avatar)
    }

    private func redraw(email: String) {
        guard let table else { return }
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound..<visible.upperBound {
            guard let index = rows.commitIndex(atRow: row), commits[index].authorEmail == email else { continue }
            table.reloadData(forRowIndexes: [row], columnIndexes: [0])
        }
    }

    // MARK: Events

    func click(row: Int, extend: Bool, toggle: Bool) {
        guard let index = rows.commitIndex(atRow: row) else { return }
        viewModel.click(commits[index], extend: extend, toggle: toggle)
    }

    func move(by offset: Int, extend: Bool) {
        viewModel.selectAdjacent(offset: offset, extend: extend)
    }

    /// Return or a double-click: checks the commit out, where allowed.
    func activate(row: Int? = nil) {
        let commit = row.flatMap { rows.commitIndex(atRow: $0) }.map { commits[$0] } ?? viewModel.selectedCommit
        guard let commit, viewModel.selection.count <= 1 else { return NSSound.beep() }
        actions?.requestCheckout(commit)
    }

    func selectAll() { viewModel.selectAll() }
    func copySelection() { actions?.copySHAs() }

    func pageRows(visibleHeight: CGFloat) -> Int {
        max(1, Int(visibleHeight / (drawing?.metrics.rowHeight(input?.layout ?? .graph) ?? 46)) - 1)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table, let actions, let index = rows.commitIndex(atRow: table.clickedRow) else { return }
        let commit = commits[index]
        // Right-clicking inside a multi-selection acts on all of it; elsewhere, on just that commit.
        if !viewModel.isSelected(commit) { viewModel.select(commit) }
        let selected = viewModel.selection.count > 1 ? viewModel.selectedCommits : [commit]
        actions.fill(menu, commit: commit, selected: selected)
    }
}

/// Routes clicks and keys to the view model instead of the table's own selection.
final class CommitNSTableView: GitCommitTableView {
    weak var coordinator: CommitTableCoordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let coordinator else { return }
        if event.clickCount == 2 { return coordinator.activate(row: row) }
        let flags = event.modifierFlags
        coordinator.click(row: row, extend: flags.contains(.shift), toggle: flags.contains(.command))
        // The table's own tracking starts a drag; its selection stays the view model's.
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let coordinator else { return super.keyDown(with: event) }
        let extend = event.modifierFlags.contains(.shift)
        let page = coordinator.pageRows(visibleHeight: visibleRect.height)
        switch event.specialKey {
        case .upArrow: coordinator.move(by: -1, extend: extend)
        case .downArrow: coordinator.move(by: 1, extend: extend)
        case .pageUp: coordinator.move(by: -page, extend: extend)
        case .pageDown: coordinator.move(by: page, extend: extend)
        case .home: coordinator.move(by: -Int(Int32.max), extend: extend)
        case .end: coordinator.move(by: Int(Int32.max), extend: extend)
        case .carriageReturn, .enter: coordinator.activate()
        default: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) {
        coordinator?.selectAll()
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): coordinator?.viewModel.selection.rows.isEmpty == false
        case #selector(selectAll(_:)): true
        default: super.validateUserInterfaceItem(item)
        }
    }
}
#endif
