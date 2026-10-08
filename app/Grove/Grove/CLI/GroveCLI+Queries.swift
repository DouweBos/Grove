// CLI/GroveCLI+Queries.swift
// Grove
//
// `grove stacks|branches|prs`: the same reads the app makes, printed as lines or, with --json, for scripts and agents.

import Foundation
import GroveKit

extension GroveCLI {

    @MainActor
    static func run(_ query: Query, in root: String, json: Bool) async throws -> String {
        // Loads the accounts, so pull requests come from the same host login as in the app.
        _ = HostingAccountStore.shared
        let repository = try await GitRepository(path: URL(fileURLWithPath: root))
        switch query {
        case .prs:
            let pullRequests = try await repository.pullRequests().filter { $0.state == .open }.map(PullRequestOutput.init)
            return json ? try encode(pullRequests) : pullRequests.map(\.line).joined(separator: "\n")
        case .stacks, .branches:
            let refs = RepositoryRefs(repository: repository, readsStatus: false)
            await refs.refresh()
            // Stacks read pull request bases and merges, so they wait for the host before printing.
            await refs.refreshPullRequestsNow()
            if query == .stacks {
                let stacks = refs.stacks.map(StackOutput.init)
                return json ? try encode(stacks) : stacks.map(\.lines).joined(separator: "\n")
            }
            let stackNames = Dictionary(refs.stacks.flatMap { stack in stack.layers.map { ($0.branch, stack.name) } },
                                        uniquingKeysWith: { first, _ in first })
            let branches = refs.localBranches.map { branch in
                BranchOutput(branch, pullRequest: refs.pullRequest(for: branch), stack: stackNames[branch.name])
            }
            return json ? try encode(branches) : branches.map(\.line).joined(separator: "\n")
        }
    }

    private static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

// MARK: - Output

/// The JSON shapes are what scripts depend on; rename nothing without a changeset note.
private struct PullRequestRef: Encodable {
    let number: Int
    let url: String
    let isDraft: Bool
    let isMerged: Bool

    init(_ pullRequest: BranchPullRequest) {
        number = pullRequest.number
        url = pullRequest.url
        isDraft = pullRequest.isDraft
        isMerged = pullRequest.isMerged
    }
}

private struct StackOutput: Encodable {
    struct Layer: Encodable {
        let branch: String
        let parent: String?
        let commits: Int
        let health: [String]
        let pullRequest: PullRequestRef?
        let ahead: Int
        let behind: Int
        let isHEAD: Bool
        let worktreePath: String?
    }

    let name: String
    let trunk: String
    let needsAttention: Bool
    /// Bottom to top; a split lists each side after the layer it grows from.
    let layers: [Layer]

    init(_ stack: BranchStack) {
        name = stack.name
        trunk = stack.trunk
        needsAttention = stack.needsAttention
        layers = stack.layers.map { layer in
            Layer(branch: layer.branch, parent: layer.parent, commits: layer.commits.count,
                  health: LayerHealth.allCases.filter(layer.health.contains).map(\.rawValue),
                  pullRequest: layer.pullRequest.map(PullRequestRef.init), ahead: layer.ahead, behind: layer.behind,
                  isHEAD: layer.isHEAD, worktreePath: layer.worktreePath)
        }
    }

    var lines: String {
        let header = "\(name) on \(trunk)" + (needsAttention ? " (needs attention)" : "")
        return ([header] + layers.map { layer in
            let pr = layer.pullRequest.map { " #\($0.number)" } ?? ""
            let health = layer.health.isEmpty ? "" : " [\(layer.health.joined(separator: ", "))]"
            return "  \(layer.isHEAD ? "*" : " ") \(layer.branch)\(pr)\(health)"
        }).joined(separator: "\n")
    }
}

private struct BranchOutput: Encodable {
    let name: String
    let sha: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let isHEAD: Bool
    let pullRequest: PullRequestRef?
    let stack: String?

    init(_ branch: BranchInfo, pullRequest: BranchPullRequest?, stack: String?) {
        name = branch.name
        sha = branch.targetSHA
        upstream = branch.upstream
        ahead = branch.ahead
        behind = branch.behind
        isHEAD = branch.isHEAD
        self.pullRequest = pullRequest.map(PullRequestRef.init)
        self.stack = stack
    }

    var line: String {
        let tracking = [ahead > 0 ? "ahead \(ahead)" : nil, behind > 0 ? "behind \(behind)" : nil].compactMap { $0 }
        let pr = pullRequest.map { " #\($0.number)" } ?? ""
        return "\(isHEAD ? "*" : " ") \(name)\(pr)" + (tracking.isEmpty ? "" : " [\(tracking.joined(separator: ", "))]")
    }
}

private struct PullRequestOutput: Encodable {
    let number: Int
    let title: String
    let author: String
    let head: String
    let base: String
    let isDraft: Bool
    let checks: String
    let updated: Date

    init(_ pullRequest: PullRequestInfo) {
        number = pullRequest.id
        title = pullRequest.title
        author = pullRequest.authorName
        head = pullRequest.sourceBranch
        base = pullRequest.targetBranch
        isDraft = pullRequest.isDraft
        checks = "\(pullRequest.checksStatus)"
        updated = pullRequest.updatedDate
    }

    var line: String { "#\(number) \(title) (\(head) \u{2192} \(base))\(isDraft ? " [draft]" : "")" }
}
