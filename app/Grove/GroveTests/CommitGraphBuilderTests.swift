// CommitGraphBuilderTests.swift
// GroveTests
//
// Lane assignment and line segments for linear history, forks, merges and convergence.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

private func commit(_ sha: String, _ parents: [String] = []) -> CommitInfo {
    let date = Date(timeIntervalSince1970: 0)
    return CommitInfo(id: sha, message: sha, summary: sha, body: nil,
                      authorName: "Author", authorEmail: "a@example.com", authorDate: date,
                      committerName: "Author", committerEmail: "a@example.com", committerDate: date,
                      parentIDs: parents, isSigned: false)
}

private func lines(_ node: GraphNode, _ kind: GraphLine.Kind) -> [GraphLine] {
    node.lines.filter { $0.kind == kind }
}

@MainActor
struct CommitGraphBuilderTests {

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

@MainActor
struct HistoryViewModelFilterTests {

}
