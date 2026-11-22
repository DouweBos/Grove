// DiffLayoutTests.swift
// GroveUIKitTests
//
// Wrapping, big diffs, the app's rows, and a diff inside the app's scroll view.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
@Suite(.serialized)
struct DiffLayoutTests {

    private func long(_ lines: Int) -> DiffResult {
        DiffFixture.diff([String(repeating: "+", count: lines)]) { index in
            "line \(index) " + String(repeating: "word ", count: index % 3 * 40)
        }
    }

    // MARK: Wrapping

    @Test func wrappedRowsAreAsTallAsTheirLines() throws {
        let probe = DiffTableProbe(size: NSSize(width: 500, height: 600))
        defer { probe.close() }
        let diff = long(6)
        probe.show(diff)
        #expect(try probe.table.rect(ofRow: 3).height == 17)
        #expect(try probe.table.frame.width > 1000, "the longest line scrolls sideways")
        probe.show(diff, wraps: true)
        let columns = try #require(probe.coordinator.geometry.wrapColumns)
        let lines = DiffWrap.lineCount(diff.hunks[0].lines[2].content, columns: columns)
        #expect(lines > 1)
        #expect(try probe.table.rect(ofRow: 3).height == CGFloat(lines) * 17)
        #expect(try probe.table.frame.width <= 500)
    }

    @Test func aNarrowerPaneRewraps() throws {
        let probe = DiffTableProbe(size: NSSize(width: 900, height: 600))
        defer { probe.close() }
        probe.show(long(6), wraps: true)
        let wide = try probe.table.rect(ofRow: 3).height
        probe.window.setContentSize(NSSize(width: 380, height: 600))
        probe.layout()
        #expect(try probe.table.rect(ofRow: 3).height > wide)
    }

    @Test func togglingWrapKeepsTheTopLineInPlace() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        let diff = long(2_000)
        probe.show(diff)
        let table = try probe.table
        let clip = try #require(table.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 1_000).minY))
        probe.layout()
        probe.show(diff, wraps: true)
        #expect(table.row(at: NSPoint(x: 1, y: clip.bounds.minY + 1)) == 1_000)
    }

    @Test func aHundredThousandWrappedLinesOnlyMakeTheRowsOnScreen() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(long(100_000), wraps: true)
        let table = try probe.table
        #expect(table.numberOfRows == 100_001)
        var made = 0
        table.enumerateAvailableRowViews { _, _ in made += 1 }
        #expect(made > 0 && made < 400)
        #expect(probe.coordinator.heights.measuredThisTurn < 5_000)
    }

    @Test func gutterAndHeaderStayWhileCodeScrollsSideways() throws {
        let probe = DiffTableProbe(size: NSSize(width: 500, height: 400))
        defer { probe.close() }
        probe.show(long(6), side: .unstaged)
        let clip = try #require(probe.table.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 300, y: 0))
        probe.layout()
        #expect(try probe.cell(1, DiffLineView.self).frame.minX == 300)
        let header = try probe.cell(0, DiffHunkHeaderView.self)
        #expect(header.frame.minX == 300 && header.frame.width == clip.bounds.width)
        #expect(try #require(header.buttons.last).frame.maxX <= header.bounds.width)
    }

    @Test func anotherFileStartsAtTheTop() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(long(500))
        let clip = try #require(probe.table.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: 2_000))
        probe.show(DiffFixture.diff([String(repeating: "+", count: 500)], path: "b.txt"))
        #expect(clip.bounds.minY == 0)
    }

    @Test func aOneSidedDiffIsNeverSplit() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(DiffFixture.diff(["+++"]), layout: .split)
        #expect(probe.coordinator.geometry.layout == .inline && probe.coordinator.geometry.gutters == .new)
        probe.show(DiffFixture.diff(["-+"]), layout: .split)
        #expect(probe.coordinator.geometry.layout == .split)
    }

    // MARK: Annotations

    private func note(_ body: String, line: Int, side: GitDiffLineSide = .new) -> GitDiffAnnotation {
        GitDiffAnnotation(id: "note-\(line)", side: side, revision: body,
                          anchor: { _ in GitDiffLineAnchor(hunk: 0, line: line) }, height: { _ in 64 },
                          content: { _ in Text(body) })
    }

    @Test func annotationsGetTheirOwnHeightUnderTheirLine() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        let diff = DiffFixture.diff([" -+ "])
        probe.show(diff, annotations: GitDiffAnnotations([note("first", line: 2)], addTitle: "Add Comment") { _, _ in nil })
        #expect(probe.coordinator.rows[4].kind == .annotation(0))
        #expect(try probe.table.rect(ofRow: 4).height == 64)
        #expect(probe.coordinator.tableView(try probe.table, shouldSelectRow: 4) == false)
        probe.show(diff, annotations: GitDiffAnnotations([], addTitle: "Add Comment") { _, _ in nil })
        #expect(try probe.table.numberOfRows == 5)
    }

    @Test func theGutterPlusPicksTheLineOrTheSelection() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        var picked: [GitDiffPickedLines] = []
        let annotations = GitDiffAnnotations([], addTitle: "Add Comment") { lines, _ in
            picked.append(lines)
            return nil
        }
        let diff = DiffFixture.diff([" --++ "])
        probe.show(diff, annotations: annotations)
        #expect(probe.coordinator.gutterClicked(row: 2, x: 5))
        #expect(picked.last?.indices == [1] && picked.last?.side == nil)
        try probe.select([2, 3, 4])
        #expect(probe.coordinator.gutterClicked(row: 3, x: 5))
        #expect(picked.last?.indices == [1, 2, 3])
        #expect(!probe.coordinator.gutterClicked(row: 2, x: 120), "only the strip")

        probe.show(diff, layout: .split, annotations: annotations)
        #expect(probe.coordinator.gutterClicked(row: 2, x: probe.coordinator.geometry.half + 5))
        #expect(picked.last?.indices == [3] && picked.last?.side == .new)
        let menu = NSMenu()
        probe.coordinator.fill(menu, clickedRow: 2)
        #expect(menu.items.first?.title == "Add Comment")
    }

    // MARK: Inside the app's scroll view

    @Test func aFittedDiffOnlyMakesWhatIsOnScreen() async throws {
        let probe = DiffTableProbe(size: NSSize(width: 600, height: 400), fitsContent: true)
        defer { probe.close() }
        var height: CGFloat = 0
        probe.coordinator.onHeight = { height = $0 }
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 170_300))
        outer.documentView = document
        probe.root.frame = NSRect(x: 0, y: 200, width: 600, height: 170_049)
        document.addSubview(probe.root)
        probe.window.contentView = outer
        probe.show(DiffFixture.diff([String(repeating: " ", count: 10_000)]))
        for _ in 0..<20 where height == 0 { await Task.yield(); try await Task.sleep(for: .milliseconds(5)) }
        let table = try probe.table
        let exact: CGFloat = 32 + 10_000 * 17
        // AppKit sizes rows it hasn't asked about by those it has, so a long diff starts close.
        #expect(height == table.rect(ofRow: 10_000).maxY)
        #expect(abs(height - exact) < exact / 100)

        outer.contentView.scroll(to: NSPoint(x: 0, y: 90_000))
        outer.reflectScrolledClipView(outer.contentView)
        probe.layout()
        let inner = try #require(table.enclosingScrollView)
        #expect(inner.frame.height <= 400)
        #expect(inner.frame.minY == 89_800)
        #expect(inner.contentView.bounds.minY == 89_800, "the rows line up with where the diff is")
        var made = 0
        table.enumerateAvailableRowViews { _, _ in made += 1 }
        #expect(made < 400)
    }

    @Test func aFittedDiffsLastLineCanBeScrolledTo() async throws {
        let probe = DiffTableProbe(size: NSSize(width: 600, height: 400), fitsContent: true)
        defer { probe.close() }
        var height: CGFloat = 3_000
        probe.coordinator.onHeight = { height = $0 }
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
        outer.documentView = document
        probe.root.frame = document.bounds
        document.addSubview(probe.root)
        probe.window.contentView = outer
        let lines = 3_000
        probe.show(DiffFixture.diff([String(repeating: " ", count: lines)]))
        for _ in 0..<12 {
            document.setFrameSize(NSSize(width: 600, height: height))
            probe.root.setFrameSize(NSSize(width: 600, height: height))
            outer.contentView.scroll(to: NSPoint(x: 0, y: max(0, height - outer.contentView.bounds.height)))
            probe.layout()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        let table = try probe.table
        #expect(abs(table.rect(ofRow: lines).maxY - height) < 1)
        #expect(table.rows(in: table.visibleRect).contains(lines))
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
#endif
