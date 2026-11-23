// CommitDayGroupTests.swift
// GroveUIKitTests
//
// History date headers: in topological order a day can recur, and each run still needs its own group.

#if os(macOS)
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
