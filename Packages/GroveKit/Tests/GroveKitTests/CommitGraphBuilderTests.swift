// CommitGraphBuilderTests.swift
// GroveKitTests
//
// Lane assignment and line segments for linear history, forks, merges and convergence.

import Foundation
import Testing
@testable import GroveKit

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

    @Test func emptyInputYieldsNoNodes() {
        #expect(CommitGraphBuilder().buildGraph(from: []).isEmpty)
    }

    @Test func linearHistoryStaysInOneLaneAndColor() {
        let nodes = CommitGraphBuilder().buildGraph(from: [commit("a", ["b"]), commit("b", ["c"]), commit("c")])
        #expect(nodes.map(\.column) == [0, 0, 0])
        #expect(Set(nodes.map(\.colorIndex)).count == 1)
        #expect(lines(nodes[0], .incoming).isEmpty)
        #expect(lines(nodes[0], .outgoing).count == 1)
        #expect(lines(nodes[1], .incoming).count == 1)
        #expect(lines(nodes[2], .outgoing).isEmpty)
    }

    @Test func mergeOpensSecondLaneWithOwnColor() {
        // M merges B (second parent) into A's line.
        let nodes = CommitGraphBuilder().buildGraph(from: [
            commit("M", ["A", "B"]), commit("A", ["R"]), commit("B", ["R"]), commit("R")
        ])
        let merge = nodes[0]
        #expect(merge.isMerge)
        let outgoing = lines(merge, .outgoing)
        #expect(outgoing.map(\.toColumn) == [0, 1])
        #expect(outgoing[0].colorIndex != outgoing[1].colorIndex)
        #expect(nodes[2].column == 1)
        // While A is drawn, B's lane passes through column 1.
        #expect(lines(nodes[1], .passThrough).map(\.fromColumn) == [1])
    }

    @Test func forkedLanesConvergeIntoSharedParent() {
        let nodes = CommitGraphBuilder().buildGraph(from: [
            commit("M", ["A", "B"]), commit("A", ["R"]), commit("B", ["R"]), commit("R", ["S"]), commit("S")
        ])
        let root = nodes[3]
        #expect(root.column == 0)
        #expect(Set(lines(root, .incoming).map(\.fromColumn)) == [0, 1])
        // Nothing may keep dangling after the lanes converged.
        #expect(lines(nodes[4], .passThrough).isEmpty)
        #expect(lines(nodes[4], .incoming).count == 1)
    }

    @Test func twoBranchTipsGetSeparateLanes() {
        let nodes = CommitGraphBuilder().buildGraph(from: [commit("A", ["C"]), commit("B", ["C"]), commit("C")])
        #expect(nodes[0].column != nodes[1].column)
        #expect(nodes[2].column == 0)
        #expect(lines(nodes[2], .incoming).count == 2)
    }

    @Test func rootReleasesLaneForReuse() {
        let nodes = CommitGraphBuilder().buildGraph(from: [commit("X"), commit("Y")])
        #expect(nodes.map(\.column) == [0, 0])
    }

    @Test func octopusMergeHasOutgoingLinePerParent() {
        let nodes = CommitGraphBuilder().buildGraph(from: [
            commit("O", ["P1", "P2", "P3"]), commit("P1"), commit("P2"), commit("P3")
        ])
        #expect(lines(nodes[0], .outgoing).count == 3)
        #expect(Set(lines(nodes[0], .outgoing).map(\.toColumn)).count == 3)
    }

    @Test func lanesAboveListsLinesEnteringFromTheTop() {
        let nodes = CommitGraphBuilder().buildGraph(from: [
            commit("M", ["A", "B"]), commit("A", ["R"]), commit("B", ["R"]), commit("R")
        ])
        #expect(Set(nodes[1].lanesAbove.map(\.fromColumn)) == [0, 1])
        #expect(nodes[0].lanesAbove.isEmpty)
    }
}

@MainActor
struct CommitDateFormatTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

}

@MainActor
struct HistoryViewModelFilterTests {
    @Test func filterMatchesMessageAuthorAndSHA() async {
        let vm = HistoryViewModel(repository: MockGitRepository())
        await vm.loadInitial()
        guard let sample = vm.commits.first else { return #expect(Bool(false), "mock log is empty") }

        vm.setSearchText(String(sample.id.prefix(6)))
        #expect(vm.filteredCommits.contains { $0.id == sample.id })

        vm.setSearchText(sample.authorName.uppercased())
        let needle = sample.authorName.lowercased()
        #expect(vm.filteredCommits.allSatisfy {
            $0.authorName.lowercased() == needle || $0.message.lowercased().contains(needle)
                || $0.authorEmail.lowercased().contains(needle)
        })

        vm.setSearchText("no-commit-matches-this-\(UUID().uuidString)")
        #expect(vm.filteredCommits.isEmpty)
    }

    @Test func loadIfNeededOnlyLoadsOnce() async {
        let vm = HistoryViewModel(repository: MockGitRepository())
        await vm.loadIfNeeded()
        let first = vm.commits.count
        await vm.loadIfNeeded()
        #expect(vm.commits.count == first)
    }
}
