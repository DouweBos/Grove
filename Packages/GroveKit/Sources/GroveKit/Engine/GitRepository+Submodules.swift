// Engine/GitRepository+Submodules.swift
// GroveKit
//
// Submodule actions beyond listing: init, update, fetch, add and a full remove.

import Foundation
import os

extension GitRepository {

    /// Clones and checks out the recorded commit, nested submodules included.
    public func initSubmodule(path submodule: String) async throws {
        Logger.gitRepository.info("Initializing submodule '\(submodule, privacy: .public)'")
        try await shell.run(["submodule", "update", "--init", "--recursive", "--", submodule])
    }

    /// Checks out the commit this repository records, or with `toRemote` the tip of the submodule's tracked branch.
    public func updateSubmodule(path submodule: String, toRemote: Bool) async throws {
        Logger.gitRepository.info("Updating submodule '\(submodule, privacy: .public)'\(toRemote ? " to remote" : "", privacy: .public)")
        try await shell.run(["submodule", "update", "--init", "--recursive"] + (toRemote ? ["--remote"] : []) + ["--", submodule])
    }

    public func fetchSubmodule(path submodule: String) async throws {
        try await shell.run(["-C", submodule, "fetch", "--all", "--prune"])
    }

    /// `git submodule add`, which clones `url` into `path` and stages `.gitmodules` and the new gitlink.
    public func addSubmodule(url: String, path submodule: String, branch: String?) async throws {
        Logger.gitRepository.info("Adding submodule \(url, privacy: .public) at '\(submodule, privacy: .public)'")
        var args = ["submodule", "add"]
        if let branch, !branch.isEmpty { args += ["-b", branch] }
        try await shell.run(args + ["--", url, submodule])
    }

    /// Deinit, `git rm` (which also drops its `.gitmodules` entry), then the clone kept under `.git/modules`,
    /// so adding a submodule at the same path later starts clean.
    public func removeSubmodule(path submodule: String) async throws {
        Logger.gitRepository.info("Removing submodule '\(submodule, privacy: .public)'")
        try await shell.run(["submodule", "deinit", "-f", "--", submodule])
        try await shell.run(["rm", "-f", "--", submodule])
        let commonDir = try await shell.run(["rev-parse", "--path-format=absolute", "--git-common-dir"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let modules = URL(fileURLWithPath: commonDir).appendingPathComponent("modules").appendingPathComponent(submodule)
        if await shell.runner.fileExists(at: modules) {
            try await shell.runner.removeItem(at: modules)
        }
    }
}
