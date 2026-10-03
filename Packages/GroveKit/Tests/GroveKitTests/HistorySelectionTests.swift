// HistorySelectionTests.swift
// GroveKitTests
//
// History multi-selection: ranges, toggles and Shift-arrows keep the focused commit in the detail pane.

import Testing
@testable import GroveKit

@MainActor
struct HistorySelectionTests {

    private func loaded() async throws -> (HistoryViewModel, [CommitInfo]) {
        let vm = HistoryViewModel(repository: MockGitRepository())
        await vm.loadInitial()
        let commits = Array(vm.commits.prefix(4))
        try #require(commits.count == 4)
        return (vm, commits)
    }

    @Test func shiftClickSelectsARangeAndFocusesTheClickedCommit() async throws {
        let (vm, commits) = try await loaded()
        vm.click(commits[0], extend: false, toggle: false)
        vm.click(commits[2], extend: true, toggle: false)
        #expect(vm.selectedCommits.map(\.id) == commits[0...2].map(\.id))
        #expect(vm.selectedCommit?.id == commits[2].id)
    }

    @Test func commandClickTogglesAndMovesFocusOff() async throws {
        let (vm, commits) = try await loaded()
        vm.click(commits[1], extend: false, toggle: false)
        vm.click(commits[3], extend: false, toggle: true)
        #expect(vm.selection.count == 2)
        vm.click(commits[3], extend: false, toggle: true)
        #expect(vm.selectedCommits.map(\.id) == [commits[1].id])
        #expect(vm.selectedCommit?.id == commits[1].id)
    }

    @Test func shiftArrowExtendsAndPlainArrowCollapses() async throws {
        let (vm, commits) = try await loaded()
        vm.select(commits[0])
        vm.selectAdjacent(offset: 1, extend: true)
        vm.selectAdjacent(offset: 1, extend: true)
        #expect(vm.selection.count == 3)
        #expect(vm.selectedCommit?.id == commits[2].id)
        vm.selectAdjacent(offset: 1)
        #expect(vm.selectedCommits.map(\.id) == [commits[3].id])
    }

    @Test func reloadKeepsTheSelection() async throws {
        let (vm, commits) = try await loaded()
        vm.click(commits[1], extend: false, toggle: false)
        vm.click(commits[2], extend: true, toggle: false)
        await vm.reload()
        #expect(vm.selection.count == 2)
        #expect(vm.selectedCommit?.id == commits[2].id)
    }
}
