// FixtureGenerator.swift
// GroveTests
//
// Builds a fixture: a bare "origin" with the full history, a clone with local branches, worktrees and submodules.

import Foundation

struct FixtureResult {
    let root: URL
    let repo: URL
    let origin: URL
    let worktrees: [URL]
    let submodules: [URL]
    let commits: Int
    let localBranches: Int
    let remoteBranches: Int
    let tags: Int
    let stashes: Int
    let seconds: Double

    var summary: String {
        """
        repo:        \(repo.path)
        origin:      \(origin.path)
        worktrees:   \(worktrees.count)\(worktrees.isEmpty ? "" : " in \(root.appendingPathComponent("worktrees").path)")
        submodules:  \(submodules.count)
        commits:     \(commits)
        branches:    \(localBranches) local, \(remoteBranches) remote-tracking
        tags:        \(tags)
        stashes:     \(stashes)
        time:        \(String(format: "%.1f", seconds))s
        """
    }
}

final class FixtureGenerator {

    static let markerName = ".grove-fixture"

    let spec: FixtureSpec
    let root: URL
    var repo: URL { root.appendingPathComponent("repo") }
    var origin: URL { root.appendingPathComponent("origin.git") }
    /// Dates for commits made after the generated history, so they are reproducible too.
    var clock: Int

    private(set) var localBranchNames: [String] = []

    init(spec: FixtureSpec, root: URL) {
        self.spec = spec
        self.root = root
        clock = Int(spec.endDate.timeIntervalSince1970) + 3_600
    }

    func generate() throws -> FixtureResult {
        try spec.validate()
        let started = Date()
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path),
           !(try manager.contentsOfDirectory(atPath: root.path)).isEmpty {
            throw FixtureError.invalid("\(root.path) is not empty")
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let links = try makeSubmoduleRepositories()
        let features = try writeOrigin(links: links)
        try FixtureGit.run(["clone", "-q", origin.path, repo.path], in: root)
        try configure(repo)
        if !links.isEmpty {
            try FixtureGit.run(["-c", "protocol.file.allow=always", "submodule", "update", "--init", "-q"], in: repo)
        }
        try createLocalBranches(features)
        try addWorktrees()
        try applyStates()
        // Marks a finished fixture: caches reuse it and `--force` may delete it.
        try Data(spec.cacheKey.utf8).write(to: root.appendingPathComponent(Self.markerName))
        return try Self.describe(root: root, seconds: Date().timeIntervalSince(started))
    }

    func tick() -> Int {
        clock += 300
        return clock
    }

    // MARK: - Origin

    private func makeSubmoduleRepositories() throws -> [FixtureSubmoduleLink] {
        try (0..<spec.submodules).map { index in
            let bare = root.appendingPathComponent("submodules/sub-\(index).git")
            try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
            try FixtureGit.run(["init", "-q", "--bare", "-b", "main"], in: bare)
            var subSpec = FixtureSpec(.small, seed: spec.seed &+ UInt64(index + 1))
            (subSpec.commits, subSpec.files, subSpec.tags) = (20 + index * 5, 12, 0)
            _ = try importHistory(subSpec, into: bare, featureCount: 0, links: [])
            let sha = try FixtureGit.run(["rev-parse", "refs/heads/main"], in: bare)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Relative URLs resolve against origin, so SHAs don't depend on where the fixture lives.
            return FixtureSubmoduleLink(path: "libs/shared-\(index)", url: "../submodules/sub-\(index).git", sha: sha)
        }
    }

    private var localCount: Int { spec.branches - 1 }
    private var localOnlyCount: Int { localCount / 5 }

    private func writeOrigin(links: [FixtureSubmoduleLink]) throws -> [FixtureHistory.Feature] {
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FixtureGit.run(["init", "-q", "--bare", "-b", "main"], in: origin)
        let featureCount = max(spec.remoteBranches, localCount - localOnlyCount) + localOnlyCount
        return try importHistory(spec, into: origin, featureCount: featureCount, links: links)
    }

    private func importHistory(_ spec: FixtureSpec, into bare: URL, featureCount: Int,
                               links: [FixtureSubmoduleLink]) throws -> [FixtureHistory.Feature] {
        let streamURL = root.appendingPathComponent(".fast-import-\(bare.lastPathComponent).stream")
        defer { try? FileManager.default.removeItem(at: streamURL) }
        let writer = try FixtureStreamWriter(url: streamURL)
        let history = FixtureHistory(spec: spec, out: writer)
        history.write(featureCount: featureCount, submodules: links)
        writer.close()
        try FixtureGit.run(["fast-import", "--quiet"], in: bare, input: streamURL)
        return history.features
    }

    private func configure(_ repository: URL) throws {
        let settings = [("user.name", "Fixture Bot"), ("user.email", "fixture@example.com"),
                        ("commit.gpgsign", "false"), ("tag.gpgsign", "false"),
                        ("protocol.file.allow", "always"), ("gc.auto", "0")]
        for (key, value) in settings { try FixtureGit.run(["config", key, value], in: repository) }
    }

    // MARK: - Branches

    /// Mostly recent branches, plus some old ones that go stale; the oldest picks are never pushed.
    private func createLocalBranches(_ features: [FixtureHistory.Feature]) throws {
        guard localCount > 0, !features.isEmpty else { return }
        var rng = FixtureRandom(seed: spec.seed &+ 99)
        let byRecency = features.sorted { $0.lastDate > $1.lastDate }.map(\.name)
        let recent = min(byRecency.count, (localCount * 3 + 4) / 5)
        var chosen = Array(byRecency.prefix(recent))
        var older = Array(byRecency.dropFirst(recent))
        while chosen.count < localCount, !older.isEmpty {
            chosen.append(older.remove(at: rng.int(older.count)))
        }
        let localOnly = Set(chosen.suffix(localOnlyCount))
        localBranchNames = chosen

        let tips = Dictionary(uniqueKeysWithValues: FixtureGit.lines(
            try FixtureGit.run(["for-each-ref", "--format=%(refname:lstrip=3) %(objectname)", "refs/remotes/origin"], in: repo)
        ).compactMap { line -> (String, String)? in
            let parts = line.split(separator: " ")
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        })
        var localUpdates = "", originDeletes = "", config = ""
        for name in chosen {
            guard let sha = tips[name] else { continue }
            localUpdates += "create refs/heads/\(name) \(sha)\n"
            if localOnly.contains(name) {
                localUpdates += "delete refs/remotes/origin/\(name)\n"
                originDeletes += "delete refs/heads/\(name)\n"
            } else {
                config += "[branch \"\(name)\"]\n\tremote = origin\n\tmerge = refs/heads/\(name)\n"
            }
        }
        try updateRefs(localUpdates, in: repo)
        try updateRefs(originDeletes, in: origin)
        let configURL = repo.appendingPathComponent(".git/config")
        let handle = try FileHandle(forWritingTo: configURL)
        handle.seekToEndOfFile()
        handle.write(Data(config.utf8))
        try handle.close()
    }

    func updateRefs(_ commands: String, in repository: URL) throws {
        guard !commands.isEmpty else { return }
        let url = root.appendingPathComponent(".update-ref-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(commands.utf8).write(to: url)
        try FixtureGit.run(["update-ref", "--stdin"], in: repository, input: url)
    }

    // MARK: - Worktrees

    private func addWorktrees() throws {
        guard spec.worktrees > 0 else { return }
        let folder = root.appendingPathComponent("worktrees")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<spec.worktrees {
            if index < localBranchNames.count {
                let name = localBranchNames[index]
                let path = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
                try FixtureGit.run(["worktree", "add", "-q", path.path, name], in: repo)
            } else {
                let path = folder.appendingPathComponent("detached-\(index)")
                try FixtureGit.run(["worktree", "add", "-q", "--detach", path.path, "HEAD~\(index)"], in: repo)
            }
        }
    }

    /// Registers a worktree then deletes its folder, as when a user removes it in Finder.
    func addMissingWorktree() throws {
        let path = root.appendingPathComponent("worktrees/deleted-in-finder")
        try FixtureGit.run(["worktree", "add", "-q", "--detach", path.path, "HEAD~1"], in: repo)
        try FileManager.default.removeItem(at: path)
    }

    // MARK: - Summary

    /// Reads counts back from disk, so a cached fixture reports the same summary as a fresh one.
    static func describe(root: URL, seconds: Double) throws -> FixtureResult {
        let repo = root.appendingPathComponent("repo")
        func count(_ args: [String]) throws -> Int { FixtureGit.lines(try FixtureGit.run(args, in: repo)).count }
        func folders(_ name: String) -> [URL] {
            let url = root.appendingPathComponent(name)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.sorted().map { url.appendingPathComponent($0) }
        }
        let commits = Int(try FixtureGit.run(["rev-list", "--count", "--all"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return FixtureResult(
            root: root, repo: repo, origin: root.appendingPathComponent("origin.git"),
            worktrees: folders("worktrees"), submodules: folders("submodules"), commits: commits,
            localBranches: try count(["for-each-ref", "--format=%(refname)", "refs/heads"]),
            remoteBranches: try count(["for-each-ref", "--format=%(refname)", "refs/remotes"]),
            tags: try count(["for-each-ref", "--format=%(refname)", "refs/tags"]),
            stashes: try count(["stash", "list"]),
            seconds: seconds
        )
    }
}
