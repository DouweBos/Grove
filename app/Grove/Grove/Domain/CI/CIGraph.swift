// Domain/CI/CIGraph.swift
// Grove
//
// A run's jobs as the workflow wires them: columns by `needs`, with the host's jobs laid over the definitions.

import Foundation

/// One entry under a workflow's `jobs:`.
nonisolated struct WorkflowJobDefinition: Hashable, Sendable {
    let key: String
    /// The job's `name:`; may hold `${{ }}` expressions.
    var name: String?
    var needs: [String] = []

    var title: String { name ?? key }
}

nonisolated enum WorkflowJobsParser {

    /// The jobs in file order; empty when the file has no `jobs:` this reader can see.
    static func parse(_ yaml: String) -> [WorkflowJobDefinition] {
        let lines = YAMLOutline.significantLines(yaml)
        guard let jobs = YAMLOutline.topLevel("jobs", in: lines) else { return [] }
        return YAMLOutline.children(of: jobs, in: lines).compactMap { index in
            guard let (key, _) = YAMLOutline.key(of: lines[index].text) else { return nil }
            var job = WorkflowJobDefinition(key: key)
            for property in YAMLOutline.children(of: index, in: lines) {
                guard let (name, value) = YAMLOutline.key(of: lines[property].text) else { continue }
                if name == "name" { job.name = YAMLOutline.scalar(value) }
                if name == "needs" { job.needs = YAMLOutline.list(value, at: property, in: lines) }
            }
            return job
        }
    }
}

nonisolated struct CIGraph: Hashable, Sendable {

    struct Node: Identifiable, Hashable, Sendable {
        /// The workflow's job key, or `job-<id>` for a job the definition doesn't account for.
        let id: String
        let title: String
        let needs: [String]
        /// The host's jobs for this node: one, several for a matrix, none before it's started.
        var jobs: [CIJob]
        var column = 0

        /// Nil while the host hasn't created the job yet.
        var status: CIRunStatus? {
            let statuses = jobs.map(\.status)
            guard !statuses.isEmpty else { return nil }
            for status in [CIRunStatus.failure, .inProgress, .queued, .cancelled] where statuses.contains(status) { return status }
            if statuses.allSatisfy({ $0 == .skipped }) { return .skipped }
            return statuses.contains(.success) ? .success : .neutral
        }
    }

    /// Left to right; a column's jobs only need jobs in earlier columns.
    let columns: [[Node]]

    var nodes: [Node] { columns.flatMap { $0 } }

    /// The `needs` links worth drawing, from the needed job to the one waiting on it. A link another path
    /// already implies is left out, as GitHub does, so links rarely skip a column and cut through other jobs.
    var edges: [(from: String, to: String)] {
        let needs = Dictionary(nodes.map { ($0.id, Set($0.needs)) }) { first, _ in first }
        var reachable: [String: Set<String>] = [:]
        func ancestors(of id: String, visiting: Set<String> = []) -> Set<String> {
            if let known = reachable[id] { return known }
            guard !visiting.contains(id) else { return [] }
            let direct = (needs[id] ?? []).filter { needs[$0] != nil }
            let all = direct.reduce(into: direct) { $0.formUnion(ancestors(of: $1, visiting: visiting.union([id]))) }
            reachable[id] = all
            return all
        }
        return nodes.flatMap { node in
            let direct = node.needs.filter { needs[$0] != nil }
            return direct.filter { need in !direct.contains { $0 != need && ancestors(of: $0).contains(need) } }
                .map { (from: $0, to: node.id) }
        }
    }

    static func == (lhs: CIGraph, rhs: CIGraph) -> Bool { lhs.columns == rhs.columns }
    func hash(into hasher: inout Hasher) { hasher.combine(columns) }

    /// Lays `jobs` over `definitions`. Without definitions every job stands alone in one column.
    static func build(definitions: [WorkflowJobDefinition], jobs: [CIJob]) -> CIGraph {
        var nodes = definitions.map { Node(id: $0.key, title: $0.title, needs: $0.needs, jobs: []) }
        for job in jobs {
            if let index = bestMatch(for: job.name, among: definitions) {
                nodes[index].jobs.append(job)
            } else {
                nodes.append(Node(id: "job-\(job.id)", title: job.name, needs: [], jobs: [job]))
            }
        }
        let depth = depths(of: nodes)
        var columns = Array(repeating: [Node](), count: (depth.values.max() ?? 0) + 1)
        for var node in nodes {
            node.column = depth[node.id] ?? 0
            columns[node.column].append(node)
        }
        return CIGraph(columns: ordered(columns))
    }

    /// The host names a job after its definition: `name` as is, with ` (matrix, values)` or ` / called job` after it,
    /// or with its `${{ }}` expressions filled in. The most specific definition wins.
    static func bestMatch(for name: String, among definitions: [WorkflowJobDefinition]) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, definition) in definitions.enumerated() {
            let title = definition.title
            let score: Int
            if name == title || name == definition.key {
                score = Int.max
            } else if name.hasPrefix(title + " (") || name.hasPrefix(title + " / ") || name.hasPrefix(definition.key + " / ") {
                score = title.count + 1
            } else if let template = title.range(of: "${{").map({ title[..<$0.lowerBound].trimmingCharacters(in: .whitespaces) }),
                      !template.isEmpty, name.hasPrefix(template) {
                score = template.count
            } else {
                continue
            }
            if score > (best?.score ?? -1) { best = (index, score) }
        }
        return best?.index
    }

    /// Longest chain of `needs` before each node; a cycle or a missing job counts as no dependency.
    private static func depths(of nodes: [Node]) -> [String: Int] {
        let byID = Dictionary(nodes.map { ($0.id, $0) }) { first, _ in first }
        var depth: [String: Int] = [:]
        var visiting: Set<String> = []
        func visit(_ id: String) -> Int {
            if let known = depth[id] { return known }
            guard let node = byID[id], visiting.insert(id).inserted else { return -1 }
            let value = (node.needs.map(visit).max() ?? -1) + 1
            visiting.remove(id)
            depth[id] = value
            return value
        }
        for node in nodes { _ = visit(node.id) }
        return depth
    }

    /// Orders each column by where its needed jobs sit, so links cross less; file order breaks ties.
    private static func ordered(_ columns: [[Node]]) -> [[Node]] {
        var rows: [String: Int] = [:]
        return columns.map { column in
            let sorted = column.enumerated().sorted { lhs, rhs in
                let left = barycenter(lhs.element, rows), right = barycenter(rhs.element, rows)
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
            for (row, node) in sorted.enumerated() { rows[node.id] = row }
            return sorted
        }
    }

    private static func barycenter(_ node: Node, _ rows: [String: Int]) -> Double {
        let placed = node.needs.compactMap { rows[$0] }
        return placed.isEmpty ? -1 : Double(placed.reduce(0, +)) / Double(placed.count)
    }
}
