// CommitGraphBuilderTests.swift
// GroveTests
//
// Tests for CommitGraphBuilder — covers basic topology, column assignment,
// merge commits, pass-through edges, lane reuse, edge cases, color
// consistency, and a full diamond-merge scenario.

import Foundation
import SwiftUI
import Testing
@testable import Grove

// MARK: - Helpers

private let dummyDate = Date(timeIntervalSince1970: 0)

private func makeCommit(
    sha: String,
    parentIDs: [String] = [],
    message: String = "Test"
) -> CommitInfo {
    CommitInfo(
        id: sha,
        message: message,
        summary: message,
        body: nil,
        authorName: "Author",
        authorEmail: "author@example.com",
        authorDate: dummyDate,
        committerName: "Committer",
        committerEmail: "committer@example.com",
        committerDate: dummyDate,
        parentIDs: parentIDs,
        isSigned: false
    )
}

// MARK: - CommitGraphBuilderTests

@MainActor
struct CommitGraphBuilderTests {

    // MARK: Basic Topology

    @Test func buildGraph_emptyInput_returnsEmptyOutput() {
        let builder = CommitGraphBuilder()
        let nodes = builder.buildGraph(from: [])
        #expect(nodes.isEmpty)
    }

    @Test func buildGraph_singleRootCommit_isInColumnZero() {
        let builder = CommitGraphBuilder()
        let commits = [makeCommit(sha: "aaa", parentIDs: [])]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes.count == 1)
        #expect(nodes[0].column == 0)
    }

    @Test func buildGraph_singleRootCommit_isNotMerge() {
        let builder = CommitGraphBuilder()
        let commits = [makeCommit(sha: "aaa", parentIDs: [])]
        let nodes = builder.buildGraph(from: commits)

        #expect(!nodes[0].isMerge)
    }

    @Test func buildGraph_singleRootCommit_hasNoDownwardEdge() {
        // Root commits have no parents, so no downward continuation edge is emitted.
        let builder = CommitGraphBuilder()
        let commits = [makeCommit(sha: "aaa", parentIDs: [])]
        let nodes = builder.buildGraph(from: commits)

        let downwardEdge = nodes[0].edges.first { $0.fromColumn == 0 && $0.toColumn == 0 }
        #expect(downwardEdge == nil)
    }

    @Test func buildGraph_linearHistory_nodeCountMatchesCommitCount() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "aaa", parentIDs: ["bbb"]),
            makeCommit(sha: "bbb", parentIDs: ["ccc"]),
            makeCommit(sha: "ccc", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes.count == 3)
    }

    @Test func buildGraph_linearHistory_allNodesInColumnZero() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "aaa", parentIDs: ["bbb"]),
            makeCommit(sha: "bbb", parentIDs: ["ccc"]),
            makeCommit(sha: "ccc", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes.allSatisfy { $0.column == 0 })
    }

    // MARK: Column Assignment

    @Test func buildGraph_twoBranchTips_getDistinctColumns() {
        // A and B both point to C but not to each other; they must land in
        // different columns because both are live at the same time.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "A", parentIDs: ["C"]),
            makeCommit(sha: "B", parentIDs: ["C"]),
            makeCommit(sha: "C", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        let colA = nodes[0].column
        let colB = nodes[1].column
        #expect(colA != colB)
    }

    @Test func buildGraph_twoBranchTips_commonAncestorAssignedAfterMerge() {
        // After both branch tips are processed, C should be in whichever column
        // A inherited (column 0) because A's first parent continues that lane.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "A", parentIDs: ["C"]),
            makeCommit(sha: "B", parentIDs: ["C"]),
            makeCommit(sha: "C", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].column == 0) // A takes the first free lane
        #expect(nodes[2].column == 0) // C is reached via A's first-parent lane
    }

    // MARK: Merge Commits

    @Test func buildGraph_commitWithTwoParents_isMergeTrue() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["P1", "P2"]),
            makeCommit(sha: "P1", parentIDs: []),
            makeCommit(sha: "P2", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].isMerge)
    }

    @Test func buildGraph_nonMergeCommit_isMergeFalse() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "X", parentIDs: ["Y"]),
            makeCommit(sha: "Y", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(!nodes[0].isMerge)
        #expect(!nodes[1].isMerge)
    }

    @Test func buildGraph_mergeCommit_hasDiagonalEdgeToSecondParent() {
        // The merge node must contain an edge whose fromColumn and toColumn differ,
        // representing the diagonal line reaching the second-parent lane.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["P1", "P2"]),
            makeCommit(sha: "P1", parentIDs: []),
            makeCommit(sha: "P2", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)
        let mergeNode = nodes[0]

        let diagonalEdge = mergeNode.edges.first { $0.fromColumn != $0.toColumn }
        #expect(diagonalEdge != nil)
    }

    // MARK: Pass-Through Edges

    @Test func buildGraph_parallelLane_receivesPassThroughEdge() {
        // When B is processed, lane 1 (holding B's SHA) is live but B sits in
        // column 0. Lane 1 should receive a vertical pass-through edge while
        // A occupies column 0.
        let builder = CommitGraphBuilder()
        // Newest first: A(parent C), B(parent D), C, D
        // After A is processed, lane 0 expects C; lane 1 is allocated for B.
        // When B is processed, lane 0 is still live for C → pass-through edge.
        let commits = [
            makeCommit(sha: "A", parentIDs: ["C"]),
            makeCommit(sha: "B", parentIDs: ["D"]),
            makeCommit(sha: "C", parentIDs: []),
            makeCommit(sha: "D", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)
        let nodeB = nodes[1] // B is at index 1

        // Lane 0 should be passing through while B is drawn in lane 1.
        let passThroughForLane0 = nodeB.edges.first { $0.fromColumn == 0 && $0.toColumn == 0 }
        #expect(passThroughForLane0 != nil)
    }

    // MARK: Lane Reuse

    @Test func buildGraph_rootCommit_releasesLaneForReuse() {
        // After a root commit releases its lane, the next independent tip should
        // reuse column 0 rather than always appending a new column.
        let builder = CommitGraphBuilder()
        // X is a root; after it, its lane (0) is free.
        // Y is the next tip and should land in column 0 again.
        let commits = [
            makeCommit(sha: "X", parentIDs: []),
            makeCommit(sha: "Y", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].column == 0)
        #expect(nodes[1].column == 0)
    }

    // MARK: Edge Cases

    @Test func buildGraph_octopusMerge_hasEdgeForEachAdditionalParent() {
        // A commit with 3 parents produces 2 diagonal merge edges (one per
        // non-first parent).
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "O", parentIDs: ["P1", "P2", "P3"]),
            makeCommit(sha: "P1", parentIDs: []),
            makeCommit(sha: "P2", parentIDs: []),
            makeCommit(sha: "P3", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)
        let octopusNode = nodes[0]

        let diagonalEdges = octopusNode.edges.filter { $0.fromColumn != $0.toColumn }
        #expect(diagonalEdges.count == 2)
    }

    @Test func buildGraph_outputOrderMatchesInputOrder() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "A", parentIDs: ["B"]),
            makeCommit(sha: "B", parentIDs: ["C"]),
            makeCommit(sha: "C", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].id == "A")
        #expect(nodes[1].id == "B")
        #expect(nodes[2].id == "C")
    }

    @Test func buildGraph_nodeIDsMatchCommitSHAs() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "sha1", parentIDs: ["sha2"]),
            makeCommit(sha: "sha2", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        for (node, commit) in zip(nodes, commits) {
            #expect(node.id == commit.id)
        }
    }

    // MARK: Color Consistency

    @Test func buildGraph_twoNodesInSameColumn_haveSameColor() {
        // In a linear history every commit is in column 0, so all colors match.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "A", parentIDs: ["B"]),
            makeCommit(sha: "B", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].column == nodes[1].column)
        #expect(nodes[0].color == nodes[1].color)
    }

    @Test func buildGraph_ownDownwardEdge_sameColorAsNode() {
        // The straight downward edge (fromColumn == toColumn == node.column)
        // must use the same color as the node's circle.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "A", parentIDs: ["B"]),
            makeCommit(sha: "B", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)
        let nodeA = nodes[0]

        let downwardEdge = nodeA.edges.first {
            $0.fromColumn == nodeA.column && $0.toColumn == nodeA.column
        }

        #expect(downwardEdge != nil)
        #expect(downwardEdge?.color == nodeA.color)
    }

    // MARK: Diamond Merge Scenario

    @Test func buildGraph_diamondMerge_mergeNodeIsMarkedAsMerge() {
        // M (parents: B, C) — merge commit
        // B (parents: D)
        // C (parents: D)
        // D (parents: []) — root
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["B", "C"]),
            makeCommit(sha: "B", parentIDs: ["D"]),
            makeCommit(sha: "C", parentIDs: ["D"]),
            makeCommit(sha: "D", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes[0].isMerge)
    }

    @Test func buildGraph_diamondMerge_producesFourNodes() {
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["B", "C"]),
            makeCommit(sha: "B", parentIDs: ["D"]),
            makeCommit(sha: "C", parentIDs: ["D"]),
            makeCommit(sha: "D", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        #expect(nodes.count == 4)
    }

    @Test func buildGraph_diamondMerge_branchNodesAreInDifferentColumns() {
        // B and C diverge from M and must occupy separate lanes.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["B", "C"]),
            makeCommit(sha: "B", parentIDs: ["D"]),
            makeCommit(sha: "C", parentIDs: ["D"]),
            makeCommit(sha: "D", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)

        let nodeB = nodes[1]
        let nodeC = nodes[2]
        #expect(nodeB.column != nodeC.column)
    }

    @Test func buildGraph_diamondMerge_rootHasNoParents() {
        // D is a root commit: isMerge must be false and it must have no downward edge.
        let builder = CommitGraphBuilder()
        let commits = [
            makeCommit(sha: "M", parentIDs: ["B", "C"]),
            makeCommit(sha: "B", parentIDs: ["D"]),
            makeCommit(sha: "C", parentIDs: ["D"]),
            makeCommit(sha: "D", parentIDs: [])
        ]
        let nodes = builder.buildGraph(from: commits)
        let nodeD = nodes[3]

        #expect(!nodeD.isMerge)

        let downwardEdge = nodeD.edges.first {
            $0.fromColumn == nodeD.column && $0.toColumn == nodeD.column
        }
        #expect(downwardEdge == nil)
    }
}
