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
struct HistoryViewModelFilterTests {

}
