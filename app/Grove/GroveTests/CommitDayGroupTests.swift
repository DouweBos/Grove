// CommitDayGroupTests.swift
// GroveTests
//
// History date headers: in topological order a day can recur, and each run still needs its own group.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct CommitDayGroupTests {

    @Test func recurringDayGetsItsOwnGroupWithAUniqueID() {
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let commits = [commit("a", base), commit("b", base - 5 * day), commit("c", base), commit("d", base)]
        let groups = CommitListView.groups(commits)
        #expect(groups.map { $0.commits.map(\.id) } == [["a"], ["b"], ["c", "d"]])
        #expect(Set(groups.map(\.id)).count == groups.count)
    }

    private func commit(_ id: String, _ date: Date) -> CommitInfo {
        CommitInfo(id: id, message: id, summary: id, body: nil, authorName: "T", authorEmail: "t@t", authorDate: date,
                   committerName: "T", committerEmail: "t@t", committerDate: date, parentIDs: [], isSigned: false)
    }
}
