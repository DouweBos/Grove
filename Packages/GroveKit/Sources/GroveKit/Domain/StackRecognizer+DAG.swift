// Domain/StackRecognizer+DAG.swift
// GroveKit
//
// The in-memory commit graph recognition walks: which candidate tips reach which commits, as bitsets.

import Foundation

extension StackRecognizer {

    enum PatchMatch {
        case parent(String, base: String, own: [String])
        case duplicate(of: String)
        case none
    }

    /// Commits off trunk with, for each, the candidates that reach it; O(commits × candidates / 64).
    struct DAG {
        let input: StackRecognizerInput
        /// Branches with commits off trunk, by name.
        let candidates: [String]
        private let index: [String: Int]
        private let parents: [[String]]
        private let candidateIndex: [String: Int]
        private let tips: [String: String]
        private let branchesAt: [String: [String]]
        private let formerOwners: [String: [String]]
        private let words: Int
        private var reach: [UInt64]
        private var sizes: [Int]
        private var patchSets: [Set<String>] = []

        init(_ input: StackRecognizerInput) {
            self.input = input
            let order = input.graph.order
            let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            index = positions
            parents = order.map { input.graph.parents[$0] ?? [] }
            let branches = input.branches.filter { $0.name != input.trunk && $0.isLocal && positions[$0.targetSHA] != nil }
            let tipMap = Dictionary(branches.map { ($0.name, $0.targetSHA) }, uniquingKeysWith: { first, _ in first })
            tips = tipMap
            candidates = tipMap.keys.sorted()
            candidateIndex = Dictionary(candidates.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            branchesAt = Dictionary(grouping: candidates) { tipMap[$0] ?? "" }
            var owners: [String: [String]] = [:]
            for name in candidates {
                for sha in input.formerTips[name] ?? [] where sha != tipMap[name] { owners[sha, default: []].append(name) }
            }
            formerOwners = owners
            words = max(1, (candidates.count + 63) / 64)
            reach = Array(repeating: 0, count: order.count * words)
            sizes = Array(repeating: 0, count: candidates.count)
            propagate()
            if !input.patchIDs.isEmpty { patchSets = candidates.indices.map(patchSet) }
        }

        /// Marks each tip, then hands every commit's candidates down to its parents; rev-list lists children first.
        private mutating func propagate() {
            for (candidate, name) in candidates.enumerated() {
                guard let tip = tips[name], let commit = index[tip] else { continue }
                reach[commit * words + candidate / 64] |= 1 << UInt64(candidate % 64)
            }
            for commit in 0..<parents.count {
                for parent in parents[commit] {
                    guard let target = index[parent] else { continue }
                    for word in 0..<words { reach[target * words + word] |= reach[commit * words + word] }
                }
                for candidate in reaching(commit) { sizes[candidate] += 1 }
            }
        }

        private func reaching(_ commit: Int) -> [Int] {
            var result: [Int] = []
            for word in 0..<words {
                var bits = reach[commit * words + word]
                while bits != 0 {
                    let bit = bits.trailingZeroBitCount
                    result.append(word * 64 + bit)
                    bits &= bits - 1
                }
            }
            return result
        }

        /// Candidates whose history contains `name`'s tip: `name` itself, same-tip branches and layers above it.
        private func above(_ name: String) -> Set<Int> {
            guard let tip = tips[name], let commit = index[tip] else { return [] }
            return Set(reaching(commit))
        }

        private func isBelow(_ other: String, _ above: Set<Int>) -> Bool {
            candidateIndex[other].map { !above.contains($0) } ?? false
        }

        private func patchSet(_ candidate: Int) -> Set<String> {
            var result: Set<String> = []
            for (commit, sha) in input.graph.order.enumerated()
            where reach[commit * words + candidate / 64] & (1 << UInt64(candidate % 64)) != 0 {
                if let id = input.patchIDs[sha] { result.insert(id) }
            }
            return result
        }

        /// Same-tip branches lowest first: a PR based on another in the group sits above it, then by name.
        private func ordered(_ names: [String]) -> [String] {
            guard names.count > 1 else { return names }
            let group = Set(names)
            func depth(_ name: String, _ seen: Set<String>) -> Int {
                guard let base = input.openPullRequests[name]?.baseBranch, group.contains(base), !seen.contains(base) else { return 0 }
                return 1 + depth(base, seen.union([name]))
            }
            return names.sorted { (depth($0, []), $0) < (depth($1, []), $1) }
        }

        private func fewestCommits(_ names: [String]) -> String? {
            names.min { (sizes[candidateIndex[$0]!], $0) < (sizes[candidateIndex[$1]!], $1) }
        }

        // MARK: - Graph and reflog pass

        /// First-parent walk from the tip: the nearest other tip is the parent; a former tip or a shared commit
        /// means the parent moved on without this layer.
        func walk(_ name: String) -> Resolution {
            guard let tip = tips[name] else { return Resolution(base: "", commits: [], evidence: .none) }
            let group = ordered(branchesAt[tip] ?? [name])
            if let position = group.firstIndex(of: name), position > 0 {
                return Resolution(parent: group[position - 1], base: tip, commits: [], evidence: .graph)
            }
            let above = above(name)
            var walked: [String] = []
            var current: String? = tip
            while let sha = current, let commit = index[sha] {
                if sha != tip, let here = branchesAt[sha]?.filter({ isBelow($0, above) }), let parent = ordered(here).last {
                    return Resolution(parent: parent, base: sha, commits: walked, evidence: .graph)
                }
                if let parent = fewestCommits(formerOwners[sha]?.filter { $0 != name && isBelow($0, above) } ?? []) {
                    return Resolution(parent: parent, base: sha, commits: walked, evidence: .reflog)
                }
                // Both sides of a fork reach the commit it grew from; the side with fewer commits past it is the parent.
                let shared = reaching(commit).filter { !above.contains($0) }.map { candidates[$0] }
                    .filter { other in commitsAbove(sha, on: other).map { $0 < walked.count } ?? false }
                if sha != tip, let parent = fewestCommits(shared) {
                    return diverged(from: parent, at: sha, walked: walked)
                }
                walked.append(sha)
                current = parents[commit].first
            }
            return Resolution(base: current ?? "", commits: walked, evidence: .none)
        }

        /// First-parent steps from `branch`'s tip down to `sha`, or nil when that walk doesn't pass it.
        private func commitsAbove(_ sha: String, on branch: String) -> Int? {
            var steps = 0
            var current = tips[branch]
            while let commit = current, commit != sha {
                guard let position = index[commit] else { return nil }
                steps += 1
                current = parents[position].first
            }
            return current == nil ? nil : steps
        }

        /// The parent's old commits end at the newest walked commit whose patch the parent still has.
        private func diverged(from parent: String, at sha: String, walked: [String]) -> Resolution {
            if let candidate = candidateIndex[parent], candidate < patchSets.count {
                let patches = patchSets[candidate]
                if let cut = walked.firstIndex(where: { input.patchIDs[$0].map(patches.contains) == true }) {
                    return Resolution(parent: parent, base: walked[cut], commits: Array(walked[..<cut]), evidence: .diverged)
                }
            }
            return Resolution(parent: parent, base: sha, commits: walked, evidence: .diverged)
        }

        // MARK: - Patch-id pass

        /// For a layer the graph puts on trunk: the branch holding a patch-identical copy of its oldest commits.
        func patchParent(_ name: String, own: [String]) -> PatchMatch {
            guard !patchSets.isEmpty, !own.isEmpty else { return .none }
            let oldestFirst = Array(own.reversed())
            let ids = oldestFirst.map { input.patchIDs[$0] }
            let ownSet = Set(ids.compactMap { $0 })
            let above = above(name)
            var best: (name: String, matched: Int, tipMatches: Bool, size: Int)?
            for (candidate, other) in candidates.enumerated() where other != name && !above.contains(candidate) {
                let patches = patchSets[candidate]
                let matched = ids.prefix { $0.map(patches.contains) == true }.count
                guard matched > 0 else { continue }
                if matched == ids.count {
                    if patches == ownSet, outranks(other, name) { return .duplicate(of: other) }
                    continue
                }
                let tipMatches = tips[other].flatMap { input.patchIDs[$0] } == ids[matched - 1]
                let entry = (name: other, matched: matched, tipMatches: tipMatches, size: sizes[candidate])
                if let current = best {
                    let better = (entry.matched, entry.tipMatches ? 1 : 0, -entry.size) > (current.matched, current.tipMatches ? 1 : 0, -current.size)
                    if better { best = entry }
                } else {
                    best = entry
                }
            }
            guard let best else { return .none }
            return .parent(best.name, base: oldestFirst[best.matched - 1], own: Array(own.dropLast(best.matched)))
        }

        /// Of two branches with the same patches, the one with a PR, then the checked-out one, then the first by name stays.
        private func outranks(_ lhs: String, _ rhs: String) -> Bool {
            func rank(_ name: String) -> (Int, Int, String) {
                let branch = input.branches.first { $0.name == name }
                return (input.openPullRequests[name] == nil ? 1 : 0, branch?.isHEAD == true ? 0 : 1, name)
            }
            return rank(lhs) < rank(rhs)
        }

        // MARK: - Pull request pass

        /// Still on trunk: a merged PR whose head this layer contains (a squash merge), else the open PR's base branch.
        func fallbackParent(_ name: String, _ resolution: Resolution) -> Resolution {
            for (position, sha) in resolution.commits.enumerated() {
                if let merged = input.mergedPullRequests.first(where: { $0.headBranch != name && $0.headMatches(sha) }) {
                    return Resolution(parent: merged.headBranch, base: sha, commits: Array(resolution.commits[..<position]),
                                      evidence: .mergedPullRequest, mergedParent: merged)
                }
            }
            if let base = input.openPullRequests[name]?.baseBranch, base != input.trunk, isBelow(base, above(name)) {
                return Resolution(parent: base, base: resolution.base, commits: resolution.commits, evidence: .pullRequestBase)
            }
            return resolution
        }

        /// Where a first-parent walk from `sha` leaves the stack's commits and reaches trunk.
        func trunkStop(from sha: String) -> String {
            var current = sha
            while let commit = index[current], let parent = parents[commit].first { current = parent }
            return current
        }
    }
}
