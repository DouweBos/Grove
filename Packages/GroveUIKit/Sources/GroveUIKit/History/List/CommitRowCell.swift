// History/List/CommitRowCell.swift
// GroveUIKit
//
// One row of the commit table, drawn in one view with no subviews, so 100k rows scroll like ten.

#if os(macOS)
import AppKit
import GroveKit

/// What a commit's row draws, looked up when the row appears.
struct CommitRowModel {
    let commit: CommitInfo
    /// Nil hides the graph, e.g. while the list is filtered and lanes would mislead.
    let node: GraphNode?
    let graphColumns: Int
    let refs: [CommitDisplayRef]
    let sync: CommitSyncState?
    let isHead: Bool
    /// Not one of the commits the host shows at full strength.
    let isDimmed: Bool
    let avatar: NSImage?
}

final class CommitRowCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("GitCommitRow")

    enum Content {
        case commit(CommitRowModel)
        case day(Date, lanes: [GraphLine], graphColumns: Int, showsGraph: Bool)
    }

    private var content: Content?
    private var layout = HistoryLayout.graph
    private var drawing: CommitDrawing?

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ content: Content, layout: HistoryLayout, drawing: CommitDrawing) {
        self.content = content
        self.layout = layout
        self.drawing = drawing
        switch content {
        case .commit(let model):
            toolTip = model.refs.isEmpty ? model.commit.summary
                : model.refs.map(\.fullName).joined(separator: "\n") + "\n" + model.commit.summary
            setAccessibilityLabel("\(model.commit.summary), \(model.commit.authorName), \(model.commit.shortSHA)")
        case .day(let date, _, _, _):
            toolTip = nil
            setAccessibilityLabel(date.commitDayTitle)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let content, let drawing else { return }
        bounds.clip()
        switch content {
        case .commit(let model):
            NSGraphicsContext.current?.cgContext.setAlpha(model.isDimmed ? 0.55 : 1)
            if layout == .graph { drawGraphRow(model, drawing) } else { drawTableRow(model, drawing) }
        case .day(let date, let lanes, let columns, let showsGraph):
            drawDay(date, lanes: lanes, columns: columns, showsGraph: showsGraph, drawing)
        }
    }

    // MARK: Graph layout

    /// Graph, avatar, refs and subject over a mono line of SHA, author and date.
    private func drawGraphRow(_ model: CommitRowModel, _ d: CommitDrawing) {
        let m = d.metrics
        let s = m.scale
        let height = bounds.height
        var x = (model.node == nil ? 12 : 8) * s
        if let node = model.node {
            let width = m.graphWidth(lanes: m.visibleLanes(model.graphColumns, width: bounds.width))
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: x, y: 0, width: width, height: height).clip()
            NSGraphicsContext.current?.cgContext.translateBy(x: x, y: 0)
            d.graph(node, height: height, isHead: model.isHead)
            NSGraphicsContext.restoreGraphicsState()
            x += width + 8 * s
        }
        let tint = model.node.map { d.palette.lane($0.colorIndex) }
        d.avatar(model.commit, image: model.avatar, tint: tint,
                 in: NSRect(x: x, y: (height - m.avatar) / 2, width: m.avatar, height: m.avatar))
        x += m.avatar + 8 * s
        var maxX = bounds.width - 12 * s
        if let sync = model.sync {
            maxX = d.symbol(sync.symbol, size: 11 * s, color: d.palette.secondary, maxX: maxX, midY: height / 2) - 6 * s
        }
        let titleFont = m.font(13, .medium)
        let metaFont = m.mono(12)
        let titleHeight = ceil(titleFont.ascender - titleFont.descender)
        let metaHeight = ceil(metaFont.ascender - metaFont.descender)
        let top = (height - titleHeight - 3 * s - metaHeight) / 2
        let titleMid = top + titleHeight / 2
        let subjectX = d.refs(model.refs, x: x, midY: titleMid, maxX: maxX)
        d.text(model.commit.summary, font: titleFont, color: d.palette.text,
               in: NSRect(x: subjectX, y: top, width: maxX - subjectX, height: titleHeight))
        let meta = "\(model.commit.shortSHA) · \(model.commit.authorName) · \(model.commit.authorDate.commitRelative())"
        let metaMid = top + titleHeight + 3 * s + metaHeight / 2
        var metaMax = maxX
        if model.commit.isMerge {
            let width = min(d.textWidth(meta, font: metaFont), maxX - x - 18 * s)
            d.symbol("arrow.triangle.merge", size: 11 * s, color: d.palette.secondary, maxX: x + width + 16 * s, midY: metaMid)
            metaMax = x + width
        }
        d.text(meta, font: metaFont, color: d.palette.secondary,
               in: NSRect(x: x, y: metaMid - metaHeight / 2, width: metaMax - x, height: metaHeight))
    }

    // MARK: Table layout

    /// Refs and subject, author, date and SHA in fixed columns.
    private func drawTableRow(_ model: CommitRowModel, _ d: CommitDrawing) {
        let m = d.metrics
        let s = m.scale
        let mid = bounds.height / 2
        let gap = 8 * s
        let mono = m.mono(12)
        var right = bounds.width - 12 * s
        for (value, width) in [(model.commit.shortSHA, CommitListMetrics.Column.sha),
                               (model.commit.authorDate.commitRelative(), CommitListMetrics.Column.date)] {
            let w = width * s
            d.text(value, font: mono, color: d.palette.secondary, in: NSRect(x: right - w, y: 0, width: w, height: bounds.height))
            right -= w + gap
        }
        let authorWidth = CommitListMetrics.Column.author * s
        d.text(model.commit.authorName, font: m.font(12), color: d.palette.secondary,
               in: NSRect(x: right - authorWidth, y: 0, width: authorWidth, height: bounds.height))
        right -= authorWidth + gap
        if let sync = model.sync {
            right = d.symbol(sync.symbol, size: 10 * s, color: d.palette.secondary, maxX: right, midY: mid) - 4 * s
        }
        let x = d.refs(model.refs, x: 12 * s, midY: mid, maxX: right)
        d.text(model.commit.summary, font: m.font(12, .medium), color: d.palette.text,
               in: NSRect(x: x, y: 0, width: right - x, height: bounds.height))
    }

    // MARK: Day header

    private func drawDay(_ date: Date, lanes: [GraphLine], columns: Int, showsGraph: Bool, _ d: CommitDrawing) {
        let s = d.metrics.scale
        var x = 8 * s
        if showsGraph {
            let width = d.metrics.graphWidth(lanes: d.metrics.visibleLanes(columns, width: bounds.width))
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: x, y: 0, width: width, height: bounds.height).clip()
            NSGraphicsContext.current?.cgContext.translateBy(x: x, y: 0)
            d.passThrough(lanes, height: bounds.height)
            NSGraphicsContext.restoreGraphicsState()
            x += width + 8 * s
        }
        d.text(date.commitDayTitle, font: d.metrics.font(12, .semibold), color: d.palette.secondary,
               in: NSRect(x: x, y: 0, width: bounds.width - x - 12 * s, height: bounds.height))
    }
}

/// Grove's selection: a rounded tint inset from the row's edges.
final class CommitTableRowView: NSTableRowView {
    var fill: NSColor = .selectedContentBackgroundColor
    var radius: CGFloat = 10
    var inset = NSSize(width: 4, height: 1)

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: inset.width, dy: inset.height), xRadius: radius, yRadius: radius).fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}
#endif
