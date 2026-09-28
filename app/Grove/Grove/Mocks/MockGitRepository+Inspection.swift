// Mocks/MockGitRepository+Inspection.swift
// Grove

import Foundation

extension MockGitRepository {

    func stashDiff(index: Int) async throws -> [FileDiff] {
        recordCall()
        return MockData.commitFileDiffs
    }

    func fileContents(path: String, revision: String?) async throws -> String {
        (1...56).map { "    let line\($0) = \"\(path)\"" }.joined(separator: "\n")
    }

    func mergedBranches(into base: String) async throws -> Set<String> {
        Set(MockData.branches.filter { $0.isLocal && $0.ahead == 0 && $0.behind > 0 }.map(\.name))
    }

    func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int) {
        let info = MockData.branches.first { $0.name == branch }
        return (info?.ahead ?? 0, info?.behind ?? 0)
    }

    func branchTips() async throws -> [BranchTip] {
        MockData.branches.filter(\.isLocal).map { branch in
            let commit = MockData.commits.first { $0.id == branch.targetSHA }
            return BranchTip(name: branch.name, sha: branch.targetSHA, committerDate: commit?.authorDate,
                             authorName: commit?.authorName ?? "", summary: commit?.summary ?? "")
        }
    }

    func aheadBehind(branches: [String], base: String) async throws -> [String: AheadBehind] {
        var counts: [String: AheadBehind] = [:]
        for info in MockData.branches where info.isLocal && branches.contains(info.name) {
            counts[info.name] = AheadBehind(ahead: info.ahead, behind: info.behind)
        }
        return counts
    }

    func compareBranches(base: String, compare: String) async throws -> BranchComparison {
        BranchComparison(
            onlyInBase: Array(MockData.commits.prefix(2)),
            onlyInCompare: Array(MockData.commits.dropFirst(2).prefix(4)),
            equivalentCount: 1,
            files: [ChangedFileStat(path: "Sources/App/Feature.swift", additions: 42, deletions: 7),
                    ChangedFileStat(path: "Assets/icon.png", additions: nil, deletions: nil)]
        )
    }

    func localConfigValue(_ key: String) async throws -> String? {
        MockLocalConfig.values[key]
    }

    func setLocalConfigValue(_ key: String, to value: String?) async throws {
        MockLocalConfig.values[key] = (value?.isEmpty ?? true) ? nil : value
    }

    func setRemoteURL(_ url: String, forRemote name: String) async throws {}

    func pullRequestDiff(number: Int) async throws -> [FileDiff] {
        recordCall()
        return MockData.commitFileDiffs
    }

    func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff] {
        recordCall()
        return MockData.commitFileDiffs.filter { $0.path == path }
    }

    func pullRequestCommits(number: Int) async throws -> [CommitInfo] {
        recordCall()
        return Array(MockData.commits.prefix(4))
    }
}

@MainActor
private enum MockLocalConfig {
    static var values: [String: String] = ["user.email": "dev@example.com"]
}
