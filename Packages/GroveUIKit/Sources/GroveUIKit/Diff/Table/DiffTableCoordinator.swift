// Diff/Table/DiffTableCoordinator.swift
// GroveUIKit
//
// Owns what the table shows and works out what an update changed, so only that is redone.

#if os(macOS)
import AppKit
import GroveKit

struct DiffTextSelection: Equatable {
    let row: Int
    /// Nil in the unified layout.
    let side: GitDiffLineSide?
    /// In the display text.
    let range: NSRange
}

/// Which part of a row the pointer is over: a unified line, or one side of a split pair.
enum DiffHoverSide: Equatable {
    case whole
    case old
    case new

    var lineSide: GitDiffLineSide? {
        switch self {
        case .whole: nil
        case .old: .old
        case .new: .new
        }
    }
}

final class DiffTableCoordinator: NSObject {
    private(set) var table: DiffNSTableView?
    private(set) var scroll: NSScrollView?
    private(set) var embedded: DiffEmbeddedView?
    var onHeight: ((CGFloat) -> Void)?

    private(set) var diff: DiffResult?
    private(set) var rows: [DiffRow] = []
    /// Where each hunk's rows begin.
    private(set) var hunkStarts: [Int] = []
    private(set) var annotationRows = IndexSet()
    private(set) var selectableRows = IndexSet()
    private(set) var annotations: GitDiffAnnotations?
    private(set) var staging: GitDiffStaging?
    private(set) var host = GitUIHost.system
    private(set) var style = GitUIStyle.system
    private(set) var palette = DiffPalette(.system)
    var geometry = DiffGeometry(metrics: DiffMetrics(scale: 1))
    let highlights = DiffHighlights()
    var heights = DiffRowHeights()

    private var isOneSided = false
    private var numberDigits = 1
    private var widestColumns: Int?
    private var annotationKeys: [AnnotationKey] = []
    private var reportedHeight: CGFloat = 0

    var textSelection: DiffTextSelection? {
        didSet { if textSelection != oldValue { showSelection() } }
    }

    /// The row and side whose gutter shows the +.
    var hover: (row: Int, side: DiffHoverSide)?
    /// The open composer, if any.
    var popover: NSPopover?

    lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    private struct AnnotationKey: Equatable {
        let id: String
        let side: GitDiffLineSide?
        let revision: AnyHashable
    }

    // MARK: Views

    func makeView(fitsContent: Bool) -> NSView {
        highlights.onChange = { [weak self] hunks in self?.highlightsArrived(in: hunks) }
        let table = DiffNSTableView()
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = true
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.setAccessibilityLabel("Diff")
        let column = NSTableColumn(identifier: .init("diff"))
        column.minWidth = 1
        column.maxWidth = .greatestFiniteMagnitude
        table.addTableColumn(column)
        table.coordinator = self
        table.dataSource = self
        table.delegate = self
        table.menu = menu
        table.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: table))

        let scroll = fitsContent ? DiffEmbeddedScrollView() : NSScrollView()
        scroll.contentView = DiffClipView()
        scroll.documentView = table
        scroll.hasVerticalScroller = !fitsContent
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        if fitsContent { scroll.verticalScrollElasticity = .none }
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        self.table = table
        self.scroll = scroll
        observe(NSView.frameDidChangeNotification, of: scroll.contentView, #selector(viewportChanged))
        observe(NSView.boundsDidChangeNotification, of: scroll.contentView, #selector(scrolled))

        guard fitsContent else { return scroll }
        table.postsFrameChangedNotifications = true
        observe(NSView.frameDidChangeNotification, of: table, #selector(contentResized))
        let embedded = DiffEmbeddedView(scroll: scroll)
        embedded.onSync = { [weak self] in self?.reportHeight() }
        self.embedded = embedded
        table.embedded = embedded
        return embedded
    }

    private func observe(_ name: Notification.Name, of object: NSView, _ selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: name, object: object)
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        highlights.cancel()
        popover?.close()
        popover = nil
        onHeight = nil
    }

    // MARK: Updates

    func update(_ input: DiffTableInput) {
        let previous = diff
        let diffChanged = previous.map {
            $0.filePath != input.diff.filePath || $0.hunks != input.diff.hunks
        } ?? true
        let sameFile = previous?.filePath == input.diff.filePath && staging?.side == input.staging?.side
        let keys = (input.annotations?.items ?? []).map { AnnotationKey(id: $0.id, side: $0.side, revision: $0.revision) }
        let annotationsChanged = keys != annotationKeys
        let stagingChanged = staging?.side != input.staging?.side
        let styleChanged = style != input.style
        let scaleChanged = geometry.metrics.scale != input.style.fontScale
        let wrapChanged = geometry.wraps != input.wrapsLines

        if diffChanged {
            highlights.reset(hunks: input.diff.hunks, path: input.diff.filePath)
            isOneSided = DiffRowBuilder.isOneSided(input.diff)
            geometry.gutters = isOneSided ? DiffRowBuilder.gutters(for: input.diff) : .both
            numberDigits = DiffRowBuilder.numberDigits(in: input.diff)
            widestColumns = nil
        }
        let layout: GitDiffLayout = isOneSided ? .inline : input.layout
        let layoutChanged = layout != geometry.layout
        let rowsChanged = diffChanged || layoutChanged || annotationsChanged || !sameFile
        let kept = rowsChanged && sameFile && !layoutChanged ? selectedLines(movedTo: input.diff) : [:]
        let anchor = sameFile && (wrapChanged || scaleChanged) ? topAnchor() : nil

        if rowsChanged {
            // While the rows and the diff still agree: clearing tells the delegate.
            textSelection = nil
            hover = nil
            table?.deselectAll(nil)
        }
        diff = input.diff
        staging = input.staging
        annotations = input.annotations
        annotationKeys = keys
        host = input.host
        if styleChanged {
            style = input.style
            palette = DiffPalette(input.style)
        }
        if scaleChanged {
            var next = DiffGeometry(metrics: DiffMetrics(scale: input.style.fontScale))
            next.gutters = geometry.gutters
            next.viewport = geometry.viewport
            next.scrolledX = geometry.scrolledX
            geometry = next
        }
        geometry.layout = layout
        geometry.wraps = input.wrapsLines
        geometry.gutterWidth = geometry.metrics.gutterWidth(digits: numberDigits)

        guard let table else { return }
        if rowsChanged || scaleChanged || wrapChanged {
            (scroll?.contentView as? DiffClipView)?.forgetAnchor()
        }
        if rowsChanged {
            heights.reset()
            buildRows(input.diff)
            fitColumn()
            table.reloadData()
            table.selectRowIndexes(rowsShowing(kept), byExtendingSelection: false)
            if !sameFile { scrollToTop() }
        } else if wrapChanged || scaleChanged {
            invalidateHeights()
            fitColumn()
            configureVisible()
        } else if styleChanged || stagingChanged {
            configureVisible()
        }
        if let anchor { restore(anchor) }
        if rowsChanged || wrapChanged || scaleChanged { contentResized() }
    }

    private func buildRows(_ diff: DiffResult) {
        let placements = (annotations?.items ?? []).enumerated().compactMap { index, item -> DiffPlacement? in
            guard let anchor = item.anchor(diff), diff.hunks.indices.contains(anchor.hunk),
                  diff.hunks[anchor.hunk].lines.indices.contains(anchor.line) else { return nil }
            return DiffPlacement(annotation: index, hunk: anchor.hunk, line: anchor.line)
        }
        (rows, hunkStarts, annotationRows) = DiffRowBuilder.build(diff, layout: geometry.layout, placements: placements)
        // As a set: asking row by row is a stall on Select All in a 100k-line diff.
        selectableRows = IndexSet(integersIn: 0..<rows.count)
        for start in hunkStarts { selectableRows.remove(start) }
        selectableRows.subtract(annotationRows)
    }

    /// The document is as wide as the longest line, or as what's on screen.
    func fitColumn() {
        guard let diff, let column = table?.tableColumns.first else { return }
        var columns = 0
        if geometry.layout == .inline && !geometry.wraps {
            if widestColumns == nil { widestColumns = DiffRowBuilder.widestLine(in: diff) }
            columns = widestColumns ?? 0
        }
        let width = max(1, geometry.contentWidth(columns: columns), geometry.viewport)
        if column.width != width { column.width = width }
        if geometry.wraps, let clip = scroll?.contentView, clip.bounds.minX != 0 {
            clip.scroll(to: NSPoint(x: 0, y: clip.bounds.minY))
            scroll?.reflectScrolledClipView(clip)
        }
    }

    // MARK: Height in the app's scroll view

    @objc func contentResized() {
        guard let embedded else { return }
        embedded.needsLayout = true
        reportHeight()
    }

    private func reportHeight() {
        guard let table, let scroll, embedded != nil, !rows.isEmpty, table.numberOfRows == rows.count else { return }
        var height = table.rect(ofRow: rows.count - 1).maxY
        if scroll.scrollerStyle == .legacy, let scroller = scroll.horizontalScroller, !scroller.isHidden {
            height += scroller.frame.height
        }
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        // Never during SwiftUI's update, which this can run inside.
        DispatchQueue.main.async { [weak self] in self?.onHeight?(height) }
    }
}
#endif
