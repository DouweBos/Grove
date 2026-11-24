// CommitDayGroupTests.swift
// GroveUIKitTests
//
// History date headers: in topological order a day can recur, and each run still needs its own group.

#if os(macOS)
import AppKit
import Foundation
@testable import GroveKit
import Testing
@testable import GroveUIKit

@MainActor
struct CommitDayGroupTests {

    @Test func recurringDayGetsItsOwnGroupWithAUniqueID() {
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = [commit("a", base), commit("b", base - 5 * day), commit("c", base), commit("d", base)]
        let groups = CommitListRows.groups(commits)
        #expect(groups.map { commits[$0.range].map(\.id) } == [["a"], ["b"], ["c", "d"]])
        #expect(Set(groups.map(\.id)).count == groups.count)
    }

    @Test func eachDayHeadsItsCommitsInTheGraphLayoutOnly() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = [commit("a", base), commit("b", base - 10), commit("c", base - 3 * 86_400)]
        let grouped = CommitListRows(commits, grouped: true)
        #expect(grouped.rows == [.day(base, firstCommit: 0), .commit(0), .commit(1), .day(base - 3 * 86_400, firstCommit: 2),
                                 .commit(2)])
        #expect(grouped.rowOfCommit == [1, 2, 4])
        #expect(grouped.commitIndex(atRow: 3) == nil)
        let table = CommitListRows(commits, grouped: false)
        #expect(table.rows == [.commit(0), .commit(1), .commit(2)])
        #expect(table.rowOfCommit == [0, 1, 2])
    }

    @Test func aHundredThousandCommitsGroupQuickly() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = (0..<100_000).map { commit("c\($0)", start - Double($0) * 600) }
        let began = Date()
        let rows = CommitListRows(commits, grouped: true)
        #expect(rows.rowOfCommit.count == 100_000)
        #expect(Date().timeIntervalSince(began) < 0.5)
    }

    @Test func aLongHistoryShowsAtOnceAndGetsItsDayHeadersAMomentLater() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = (0..<30_000).map { commit("c\($0)", start - Double($0) * 600) }
        let coordinator = CommitTableCoordinator(viewModel: HistoryViewModel(repository: MockGitRepository()))
        let scroll = coordinator.makeView()
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        coordinator.update(CommitTableInput(commits: commits, layout: .graph, showsGraph: false, graphColumns: 1, refsKey: 0,
                                            selection: ["c5"], focus: "c5", style: .system, ownCommits: nil, avatarURL: nil))
        #expect(coordinator.rows.count == 30_000)
        for _ in 0..<200 where coordinator.rows.count == 30_000 { try await Task.sleep(for: .milliseconds(10)) }
        let days = CommitListRows.groups(commits).count
        #expect(coordinator.rows.count == 30_000 + days)
        #expect(coordinator.table?.selectedRow == coordinator.rows.row(ofCommit: 5))
    }

    @Test func theSelectedCommitKeepsItsDayHeaderInSightOnFirstShow() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = (0..<300).map { commit("c\($0)", start - Double($0) * 3_600) }
        let coordinator = CommitTableCoordinator(viewModel: HistoryViewModel(repository: MockGitRepository()))
        let scroll = coordinator.makeView()
        let input = { (focus: String) in
            CommitTableInput(commits: commits, layout: .graph, showsGraph: false, graphColumns: 1, refsKey: 0,
                             selection: [focus], focus: focus, style: .system, ownCommits: nil, avatarURL: nil)
        }
        // Selected before the table has any height, as History is when it first shows.
        coordinator.update(input("c0"))
        try await Task.sleep(for: .milliseconds(50))
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let table = try #require(coordinator.table)
        #expect(table.visibleRect.minY == 0)

        // Further down, a day's first commit brings its header along.
        let rows = coordinator.rows
        let dayRow = try #require((0..<rows.count).last { row in
            if case .day = rows.row(row) { return row > 100 }
            return false
        })
        let first = try #require(rows.commitIndex(atRow: dayRow + 1))
        coordinator.update(input(commits[first].id))
        let visible = table.rows(in: table.visibleRect)
        #expect(visible.contains(dayRow) && visible.contains(dayRow + 1))
    }

    private func commit(_ id: String, _ date: Date) -> CommitInfo {
        CommitInfo(id: id, message: id, summary: id, body: nil, authorName: "T", authorEmail: "t@t", authorDate: date,
                   committerName: "T", committerEmail: "t@t", committerDate: date, parentIDs: [], isSigned: false)
    }
}

@MainActor
struct CommitDateFormatTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func recentDatesAreRelative() {
        #expect(now.addingTimeInterval(-20).commitRelative(now: now) == "just now")
        #expect(now.addingTimeInterval(-12 * 60).commitRelative(now: now) == "12 min ago")
    }

    @Test func oldDatesAreShortDates() {
        let old = now.addingTimeInterval(-400 * 86_400)
        #expect(old.commitRelative(now: now).contains("20"))
    }
}
#endif
