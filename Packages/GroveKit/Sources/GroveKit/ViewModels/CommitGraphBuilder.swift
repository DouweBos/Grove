// ViewModels/CommitGraphBuilder.swift
// GroveKit
//
// Assigns every commit in a newest-first list to a lane and records the line
// segments each row must draw so lanes connect seamlessly from row to row.

import Foundation

// MARK: - GraphNode

/// Drawing information for a single commit row.
struct GraphNode: Identifiable, Equatable {
    let id: String
    /// Lane of the commit dot (left = 0).
    let column: Int
    /// Index into the app's lane palette; stays stable for the lifetime of a lane.
    let colorIndex: Int
    let lines: [GraphLine]
    let isMerge: Bool

    /// Lanes entering the row from above, used to continue lines through non-commit rows.
    var lanesAbove: [GraphLine] {
        lines.filter { $0.kind != .outgoing }
    }
}

// MARK: - GraphLine

/// A segment inside one row. Pass-through lines span the whole row; incoming
/// lines end at the dot, outgoing lines start at the dot.
struct GraphLine: Equatable {
    enum Kind: Equatable { case passThrough, incoming, outgoing }

    let kind: Kind
    /// Column at the top of the segment (the dot's column for outgoing lines).
    let fromColumn: Int
    /// Column at the bottom of the segment (the dot's column for incoming lines).
    let toColumn: Int
    let colorIndex: Int
}

// MARK: - CommitGraphBuilder

/// Builds ``GraphNode`` values for commits ordered children-before-parents.
///
/// Every lane slot holds the SHA it expects next. When several lanes expect the
/// same commit (branches forking from it) they all converge into its dot.
/// Lanes never shift sideways, so a column keeps its color while it's alive.
struct CommitGraphBuilder {

    private struct Lane {
        let sha: String
        let colorIndex: Int
    }

    func buildGraph(from commits: [CommitInfo]) -> [GraphNode] {
        var lanes: [Lane?] = []
        var nextColor = 0
        var nodes: [GraphNode] = []
        nodes.reserveCapacity(commits.count)

        func allocate(_ sha: String, color: Int) -> Int {
            let lane = Lane(sha: sha, colorIndex: color)
            if let free = lanes.firstIndex(where: { $0 == nil }) {
                lanes[free] = lane
                return free
            }
            lanes.append(lane)
            return lanes.count - 1
        }

        for commit in commits {
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

            nodes.append(GraphNode(
                id: commit.id,
                column: column,
                colorIndex: colorIndex,
                lines: lines,
                isMerge: commit.isMerge
            ))
        }
        return nodes
    }
}
