// Engine/GitRepository+Options.swift
// GroveKit
//
// The less common forms of merge, stash and remote commands.

import Foundation

extension GitRepository {

    public func merge(branch: String, squash: Bool) async throws {
        guard squash else { return try await merge(branch: branch) }
        try await shell.run(["merge", "--squash", branch])
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }

    public func stashCreate(message: String?, includeUntracked: Bool, keepIndex: Bool, paths: [String]?) async throws {
        guard keepIndex else {
            return try await stashCreate(message: message, includeUntracked: includeUntracked, paths: paths)
        }
        var args = ["stash", "push", "--keep-index"]
        if includeUntracked { args.append("--include-untracked") }
        if let message { args += ["-m", message] }
        if let paths, !paths.isEmpty { args += ["--"] + paths }
        try await shell.run(args)
    }

    public func stashBranch(index: Int, name: String) async throws {
        try await shell.run(["stash", "branch", name, "stash@{\(index)}"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    public func renameRemote(from old: String, to new: String) async throws {
        try await shell.run(["remote", "rename", old, new])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    public func pruneRemote(name: String) async throws {
        try await shell.run(["remote", "prune", name])
    }
}
