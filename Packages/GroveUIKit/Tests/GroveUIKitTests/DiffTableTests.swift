// DiffTableTests.swift
// GroveUIKitTests
//
// The table as an app drives it: in a window that never shows.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
@Suite(.serialized)
struct DiffTableTests {

    private let edit = DiffFixture.diff([" -+ ", " ++ "])

    // MARK: Actions

    @Test func selectedLinesNarrowAHunksButtons() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        #expect(try probe.buttons() == ["Discard Hunk", "Stage Hunk"])
        try probe.select([2, 3])
        #expect(try probe.buttons() == ["Discard Lines", "Stage Lines"])
        #expect(try probe.buttons(5) == ["Discard Hunk", "Stage Hunk"])
        try probe.select([1])
        #expect(try probe.buttons() == ["Discard Hunk", "Stage Hunk"], "context alone selects no change")
    }

    @Test func theStagedSideUnstages() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .staged)
        #expect(try probe.buttons() == ["Unstage Hunk"])
        try probe.select([2])
        #expect(try probe.buttons() == ["Unstage Lines"])
        probe.show(edit)
        #expect(try probe.buttons().isEmpty)
    }

    @Test func aButtonActsOnItsHunkAndTheSelectedChanges() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        try probe.select([1, 2, 3])
        try #require(probe.cell(0, DiffHunkHeaderView.self).buttons.last).performClick(nil)
        let acted = try #require(probe.acted.first)
        #expect(acted.action == .stageLines && acted.hunk == edit.hunks[0])
        #expect(acted.lines == [edit.hunks[0].lines[1], edit.hunks[0].lines[2]])
        #expect(try probe.table.selectedRowIndexes.isEmpty)
    }

    @Test func aWholeHunkSendsNoLines() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        probe.coordinator.perform(.stageHunk, hunk: 1, id: edit.hunks[1].id)
        #expect(probe.acted.first?.hunk == edit.hunks[1] && probe.acted.first?.lines.isEmpty == true)
    }

    @Test func anActionForAReplacedHunkDoesNothing() {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        probe.show(DiffFixture.diff([" +"]), side: .unstaged)
        probe.coordinator.perform(.discardHunk, hunk: 0, id: edit.hunks[0].id)
        probe.coordinator.perform(.discardLines, hunk: 0, id: probe.coordinator.diff?.hunks[0].id ?? "")
        #expect(probe.acted.isEmpty, "a stale hunk, and lines with none selected")
    }

    @Test func selectionFollowsTheLinesNotTheRows() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        try probe.select([7])
        let rest = DiffResult(filePath: edit.filePath, hunks: [edit.hunks[1]], stats: edit.stats)
        probe.show(rest, side: .unstaged)
        #expect(try probe.table.selectedRowIndexes == [2], "the first hunk left; the line moved up")
        probe.show(DiffFixture.diff(["--"]), side: .unstaged)
        #expect(try probe.table.selectedRowIndexes.isEmpty, "another hunk never inherits a selection")
    }

    @Test func switchingSideDropsTheSelection() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        try probe.select([2])
        probe.show(edit, side: .staged)
        #expect(try probe.table.selectedRowIndexes.isEmpty)
        #expect(try probe.buttons() == ["Unstage Hunk"])
    }

    @Test func aShorterDiffUnderASelectionIsSafe() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(DiffFixture.diff([" ++++++++", " --------"]), side: .unstaged)
        try probe.select(IndexSet(integersIn: 11..<18))
        probe.show(DiffFixture.diff(["+"]), side: .unstaged)
        #expect(try probe.table.numberOfRows == 2)
    }

    // MARK: Menu

    @Test func theMenuKeepsTheWholeHunkBesideItsLines() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged, opens: true)
        try probe.select([2])
        let menu = NSMenu()
        probe.coordinator.fill(menu, clickedRow: 2)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        #expect(titles == ["Open in Editor at Line", "Copy", "Stage Lines", "Discard Lines", "Stage Hunk", "Discard Hunk"])
    }

    @Test func rightClickingAHeaderKeepsTheSelection() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        try probe.select([2])
        probe.coordinator.fill(NSMenu(), clickedRow: 0)
        #expect(try probe.table.selectedRowIndexes == [2])
    }

    @Test func aRemovedLineOpensWhereItWas() {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, opens: true)
        #expect(probe.coordinator.newLine(at: 2) == 2)
        #expect(probe.coordinator.optionClicked(row: 3))
        #expect(probe.opened.first?.path == "a.txt" && probe.opened.first?.line == 2)
        probe.show(edit)
        #expect(!probe.coordinator.optionClicked(row: 3), "no host to open it")
    }

    // MARK: Copy

    @Test func selectedLinesCopyThroughTheHost() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit)
        try probe.select([1, 2])
        try probe.table.copy(nil)
        #expect(probe.copied == ["line 0\nline 1"])
    }

    @Test func draggingAlongALineSelectsItsText() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit)
        probe.coordinator.selectText(row: 2, side: nil, range: NSRange(location: 2, length: 3))
        #expect(try probe.cell(2, DiffLineView.self).textSelection?.range.length == 3)
        try probe.table.copy(nil)
        #expect(probe.copied == ["ne "])
        try probe.select([3])
        #expect(probe.coordinator.textSelection == nil, "selecting lines replaces it")
    }

    @Test func aClickOnTheOnlySelectedLineTakesItBack() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit)
        probe.coordinator.clicked(row: 2)
        #expect(try probe.table.selectedRowIndexes == [2])
        probe.coordinator.clicked(row: 2)
        #expect(try probe.table.selectedRowIndexes.isEmpty)
        probe.coordinator.selectRows(from: 6, to: 3)
        #expect(try probe.table.selectedRowIndexes == [3, 4, 6], "headers aren't selectable")
    }

    @Test func aMouseDragSelectsTextThenRows() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit)
        let table = try probe.table
        let coordinator = probe.coordinator
        let textX = coordinator.geometry.textX
        let width = coordinator.geometry.metrics.characterWidth
        let start = NSPoint(x: textX + 1, y: table.rect(ofRow: 2).midY)
        let code = try #require(coordinator.codeSide(row: 2, x: start.x))
        let text = try #require(coordinator.text(inRow: 2, side: code.side))
        let anchor = coordinator.textOffset(in: text, row: 2, origin: code.origin, point: start)
        var drag = DiffNSTableView.CodeDrag(row: 2, side: code.side, origin: code.origin, text: text, start: start, anchor: anchor)
        table.drag(&drag, to: NSPoint(x: textX + 4 * width, y: start.y))
        #expect(drag.hasMoved)
        #expect(coordinator.copySelection() == "line")
        table.drag(&drag, to: NSPoint(x: textX + 4 * width, y: table.rect(ofRow: 3).midY))
        #expect(table.selectedRowIndexes == [2, 3])
        #expect(coordinator.codeSide(row: 2, x: textX - 2) == nil, "the gutter selects lines")
    }

    // MARK: Looks

    @Test func aStyleChangeRepaintsWithoutRebuilding() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit, side: .unstaged)
        try probe.select([2])
        var style = GitUIStyle.system
        style.success = Color(red: 0, green: 0, blue: 1)
        probe.show(edit, side: .unstaged, style: style)
        #expect(probe.coordinator.palette.added.usingColorSpace(.sRGB)?.blueComponent == 1)
        #expect(try probe.table.selectedRowIndexes == [2])
    }

    @Test func zoomResizesLiveRows() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        probe.show(edit)
        #expect(try probe.table.rect(ofRow: 1).height == 17)
        var style = GitUIStyle.system
        style.fontScale = 17 / 13
        probe.show(edit, style: style)
        #expect(probe.coordinator.geometry.metrics.font.pointSize > 12)
        #expect(try probe.table.rect(ofRow: 1).height == 22)
        #expect(try probe.table.rect(ofRow: 0).height == 42)
    }

    @Test func thePointerShowsTheHandOnlyWhenTheHostWantsIt() throws {
        let probe = DiffTableProbe()
        defer { probe.close() }
        let annotations = GitDiffAnnotations([], addTitle: "Add Comment") { _, _ in nil }
        var style = GitUIStyle.system
        probe.show(edit, side: .unstaged, annotations: annotations, style: style)
        #expect(probe.coordinator.cursor(row: 2, x: 4) == nil)
        style.showsPointingHand = true
        probe.show(edit, side: .unstaged, annotations: annotations, style: style)
        #expect(probe.coordinator.cursor(row: 2, x: 4) == NSCursor.pointingHand)
        #expect(probe.coordinator.cursor(row: 2, x: 300) == NSCursor.arrow)
        let button = try #require(probe.cell(0, DiffHunkHeaderView.self).buttons.first)
        #expect(probe.coordinator.cursor(row: 0, x: button.frame.midX) == NSCursor.pointingHand)
    }
}
#endif
