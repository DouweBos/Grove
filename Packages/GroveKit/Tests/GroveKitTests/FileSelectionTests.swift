// FileSelectionTests.swift
// GroveKitTests
//
// Changes-list selection: click, Cmd-click, Shift-click, arrows, and following files across sides.

import Testing
@testable import GroveKit

struct FileSelectionTests {

    private let order = ["a", "b", "c", "d"].map { FileRow(path: $0, side: .unstaged) }

    @Test func clickSelectsOnlyThatRow() {
        var selection = FileSelection()
        selection.click(order[0], in: order, extend: false, toggle: false)
        selection.click(order[2], in: order, extend: false, toggle: false)
        #expect(selection.rows == [order[2]])
        #expect(selection.focus == order[2])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchor() {
        var selection = FileSelection()
        selection.click(order[1], in: order, extend: false, toggle: false)
        selection.click(order[3], in: order, extend: true, toggle: false)
        #expect(selection.rows == Set(order[1...3]))
        selection.click(order[0], in: order, extend: true, toggle: false)
        #expect(selection.rows == Set(order[0...1]))
    }

    @Test func commandClickTogglesARow() {
        var selection = FileSelection()
        selection.click(order[0], in: order, extend: false, toggle: false)
        selection.click(order[2], in: order, extend: false, toggle: true)
        #expect(selection.rows == [order[0], order[2]])
        selection.click(order[0], in: order, extend: false, toggle: true)
        #expect(selection.rows == [order[2]])
        #expect(selection.focus == order[2])
    }

    @Test func arrowsMoveAndShiftArrowsExtend() {
        var selection = FileSelection()
        selection.move(by: 1, in: order, extend: false)
        #expect(selection.rows == [order[0]])
        selection.move(by: 1, in: order, extend: true)
        selection.move(by: 1, in: order, extend: true)
        #expect(selection.rows == Set(order[0...2]))
        selection.move(by: 5, in: order, extend: false)
        #expect(selection.rows == [order[3]])
    }

    @Test func reconcileFollowsAFileToItsOtherSide() {
        var selection = FileSelection()
        selection.click(order[0], in: order, extend: false, toggle: false)
        selection.click(order[1], in: order, extend: true, toggle: false)
        // "a" was staged and "b" is gone.
        selection.reconcile { row in row.path == "a" ? FileRow(path: "a", side: .staged) : nil }
        #expect(selection.rows == [FileRow(path: "a", side: .staged)])
        #expect(selection.focus == FileRow(path: "a", side: .staged))
    }
}
