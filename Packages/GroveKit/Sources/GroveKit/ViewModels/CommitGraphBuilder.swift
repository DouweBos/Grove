// ViewModels/CommitGraphBuilder.swift
// GroveKit
//
// Assigns every commit in a newest-first list to a lane and records the line
// segments each row must draw so lanes connect seamlessly from row to row.

import Foundation

// MARK: - GraphNode

/// Drawing information for a single commit row.
public struct GraphNode: Identifiable, Equatable {
    public let id: String
    /// Lane of the commit dot (left = 0).
    public let column: Int
    /// Index into the app's lane palette; stays stable for the lifetime of a lane.
    public let colorIndex: Int
    public let lines: [GraphLine]
    public let isMerge: Bool

    /// Lanes entering the row from above, used to continue lines through non-commit rows.
    public var lanesAbove: [GraphLine] {
        lines.filter { $0.kind != .outgoing }
    }
}

// MARK: - GraphLine

/// A segment inside one row. Pass-through lines span the whole row; incoming
/// lines end at the dot, outgoing lines start at the dot.
public struct GraphLine: Equatable {
    public enum Kind: Equatable { case passThrough, incoming, outgoing }

    public let kind: Kind
    /// Column at the top of the segment (the dot's column for outgoing lines).
    public let fromColumn: Int
    /// Column at the bottom of the segment (the dot's column for incoming lines).
    public let toColumn: Int
    public let colorIndex: Int

    public init(kind: Kind, fromColumn: Int, toColumn: Int, colorIndex: Int) {
        self.kind = kind
        self.fromColumn = fromColumn
        self.toColumn = toColumn
        self.colorIndex = colorIndex
    }
}

// MARK: - CommitGraphBuilder

/// Builds ``GraphNode`` values for commits ordered children-before-parents.
///
/// Every lane slot holds the SHA it expects next. When several lanes expect the
/// same commit (branches forking from it) they all converge into its dot.
/// Lanes never shift sideways, so a column keeps its color while it's alive.
/// The builder keeps its open lanes, so a paged log appends each page without rebuilding.
public struct CommitGraphBuilder {

    private var lanes: [Lane?] = []
    private var nextColor = 0
    /// Widest column any row built so far reaches.
    public private(set) var maxColumn = 0

    public init() {
    }

    private struct Lane {
        let sha: String
        let colorIndex: Int
    }

    /// The whole graph of `commits`, from scratch.
    public func buildGraph(from commits: [CommitInfo]) -> [GraphNode] {
        var builder = CommitGraphBuilder()
        return builder.append(commits)
    }

    /// Rows for the next page of commits, continuing the lanes left open by earlier pages.
    public mutating func append(_ commits: [CommitInfo]) -> [GraphNode] {
        var nodes: [GraphNode] = []
        nodes.reserveCapacity(commits.count)
        for commit in commits {
            let node = node(for: commit)
            maxColumn = max(maxColumn, node.lines.map { max($0.fromColumn, $0.toColumn) }.max() ?? 0, node.column)
            nodes.append(node)
        }
        return nodes
    }

    private mutating func allocate(_ sha: String, color: Int) -> Int {
        let lane = Lane(sha: sha, colorIndex: color)
        if let free = lanes.firstIndex(where: { $0 == nil }) {
            lanes[free] = lane
            return free
        }
        lanes.append(lane)
        return lanes.count - 1
    }

    private mutating func node(for commit: CommitInfo) -> GraphNode {
        let matching = lanes.indices.filter { lanes[$0]?.sha == commit.id }
        var lines: [GraphLine] = []

        let column: Int
        let colorIndex: Int
        if let first = matching.first, let lane = lanes[first] {
            column = first
            colorIndex = lane.colorIndex
        } else {
            colorIndex = nextColor
            nextColor += 1
            column = lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
        }

        for index in matching {
            if let lane = lanes[index] {
                lines.append(GraphLine(kind: .incoming, fromColumn: index, toColumn: column, colorIndex: lane.colorIndex))
            }
            lanes[index] = nil
        }
        for (index, lane) in lanes.enumerated() {
            guard let lane else { continue }
            lines.append(GraphLine(kind: .passThrough, fromColumn: index, toColumn: index, colorIndex: lane.colorIndex))
        }

        for (offset, parent) in commit.parentIDs.enumerated() {
            let target: Int
            let color: Int
            if offset == 0 {
                if column < lanes.count {
                    lanes[column] = Lane(sha: parent, colorIndex: colorIndex)
                } else {
                    lanes.append(Lane(sha: parent, colorIndex: colorIndex))
                }
                target = column
                color = colorIndex
            } else if let existing = lanes.firstIndex(where: { $0?.sha == parent }), let lane = lanes[existing] {
                target = existing
                color = lane.colorIndex
            } else {
                color = nextColor
                nextColor += 1
                target = allocate(parent, color: color)
            }
            lines.append(GraphLine(kind: .outgoing, fromColumn: column, toColumn: target, colorIndex: color))
        }

        while let last = lanes.last, last == nil { lanes.removeLast() }

        return GraphNode(id: commit.id, column: column, colorIndex: colorIndex, lines: lines, isMerge: commit.isMerge)
    }
}
