// Engine/GitRepository+Patches.swift
// GroveKit
//
// Writing working-copy changes as a patch and applying patch files.

import Foundation
import os

extension GitRepository {

    func patch(paths: [String], staged: Bool) async throws -> String {
        guard !paths.isEmpty else { return "" }
        let base = ["diff", "--binary", "--no-color", "--no-ext-diff"]
        if staged {
            return try await shell.run(base + ["--cached", "--"] + paths).stdout
        }
        // Untracked files are invisible to `git diff`, so each is diffed against nothing.
        let untrackedOutput = try await shell.run(["ls-files", "--others", "--exclude-standard", "-z", "--"] + paths).stdout
        let untracked = untrackedOutput.split(separator: "\0").map(String.init)
        let tracked = paths.filter { !untracked.contains($0) }
        var patch = tracked.isEmpty ? "" : try await shell.run(base + ["--"] + tracked).stdout
        for file in untracked {
            let result = try await shell.runAllowingFailure(base + ["--no-index", "--", "/dev/null", file])
            guard result.exitCode <= 1 else {
                throw GitShellError.nonZeroExit(command: "diff --no-index", exitCode: result.exitCode, stderr: result.stderr)
            }
            patch += result.stdout
        }
        return patch
    }

    func applyPatch(at file: URL, toIndex: Bool, checkOnly: Bool) async throws {
        var args = ["apply", "--whitespace=nowarn"]
        if toIndex { args.append("--index") }
        if checkOnly { args.append("--check") }
        args.append(file.path)
        if !checkOnly {
            Logger.gitRepository.info("Applying patch \(file.lastPathComponent, privacy: .public) in \(self.displayName, privacy: .public)")
        }
        let result = try await shell.runAllowingFailure(args)
        guard result.isSuccess else {
            throw GitRepositoryError.applyPatchFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
