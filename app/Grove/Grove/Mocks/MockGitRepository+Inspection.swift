// Mocks/MockGitRepository+Inspection.swift
// Grove

import Foundation

extension MockGitRepository {

    func stashDiff(index: Int) async throws -> [FileDiff] {
        MockData.commitFileDiffs
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

    func localConfigValue(_ key: String) async throws -> String? {
        MockLocalConfig.values[key]
    }

    func setLocalConfigValue(_ key: String, to value: String?) async throws {
        MockLocalConfig.values[key] = (value?.isEmpty ?? true) ? nil : value
    }

    func setRemoteURL(_ url: String, forRemote name: String) async throws {}

    func pullRequestDiff(number: Int) async throws -> [FileDiff] {
        MockData.commitFileDiffs
    }

    func pullRequestCommits(number: Int) async throws -> [CommitInfo] {
        Array(MockData.commits.prefix(4))
    }
}

@MainActor
private enum MockLocalConfig {
    static var values: [String: String] = ["user.email": "dev@example.com"]
}
