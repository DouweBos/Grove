// Engine/GitRepository+LFS.swift
// GroveKit
//
// Git LFS: detection, which paths LFS tracks, tracking new patterns and downloading objects after a pull.

import Foundation
import os

extension GitRepository {

    func lfsStatus() async -> LFSStatus {
        guard await Self.usesLFS(at: path, runner: shell.runner) else { return LFSStatus() }
        return LFSStatus(usesLFS: true, isInstalled: await Self.isLFSInstalled(shell: shell))
    }

    func lfsTrackedPaths(among paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let input = paths.joined(separator: "\0") + "\0"
        let result = try? await shell.runWithInput(["check-attr", "-z", "--stdin", "filter"], input: input)
        return Self.parseLFSAttributes(result?.stdout ?? "")
    }

    /// `pattern` is a gitattributes glob such as `*.psd`; `literal` tracks exactly one file.
    func trackWithLFS(pattern: String, literal: Bool) async throws {
        guard await Self.isLFSInstalled(shell: shell) else { throw GitShellError.lfsNotInstalled }
        try await shell.run(["lfs", "track"] + (literal ? ["--filename", pattern] : [pattern]))
        try await shell.run(["add", "--", ".gitattributes"])
        // An already tracked file only becomes a pointer once it's re-added through the new filter.
        if literal, try await shell.runAllowingFailure(["ls-files", "--error-unmatch", "--", pattern]).isSuccess {
            try await shell.run(["add", "--renormalize", "--", pattern])
        }
    }

    /// Downloads and checks out the LFS objects a pull brought in; nothing for repositories without LFS.
    func pullLFSObjectsIfNeeded(remote: String?) async throws {
        let status = await lfsStatus()
        guard status.usesLFS else { return }
        guard status.isInstalled else { throw GitShellError.lfsNotInstalled }
        Logger.gitRepository.info("Pulling LFS objects in \(self.displayName, privacy: .public)")
        try await shell.run(["lfs", "pull"] + (remote.map { [$0] } ?? []))
    }

    /// The real content behind an LFS pointer blob, or the blob itself when it isn't one or git-lfs can't run.
    func smudgedIfLFSPointer(_ data: Data, path file: String) async -> Data {
        guard let pointerText = LFSPointer(data: data).flatMap({ _ in String(data: data, encoding: .utf8) }),
              await Self.isLFSInstalled(shell: shell),
              let result = try? await shell.runWithInput(["lfs", "smudge", "--", file], input: pointerText) else { return data }
        return result.stdoutData
    }

    // MARK: Helpers

    /// A root `.gitattributes` with an LFS filter, or LFS objects already in the git directory.
    nonisolated static func usesLFS(at root: URL, runner: any GitRunner) async -> Bool {
        let attributes = await runner.readString(at: root.appendingPathComponent(".gitattributes")) ?? ""
        if attributes.contains("filter=lfs") { return true }
        return await runner.itemKind(at: root.appendingPathComponent(".git/lfs/objects")) == .directory
    }

    /// Only a positive answer is cached, so installing git-lfs while Grove runs is picked up.
    nonisolated private static let lfsInstalled = OSAllocatedUnfairLock(initialState: false)

    nonisolated static func isLFSInstalled(shell: GitShell) async -> Bool {
        if lfsInstalled.withLock({ $0 }) { return true }
        let installed = (try? await shell.runAllowingFailure(["lfs", "version"]))?.isSuccess ?? false
        if installed { lfsInstalled.withLock { $0 = true } }
        return installed
    }

    /// `check-attr -z` output is path, attribute, value triples separated by NUL.
    nonisolated static func parseLFSAttributes(_ output: String) -> Set<String> {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var paths: Set<String> = []
        var index = 0
        while index + 2 < fields.count {
            if fields[index + 2] == "lfs" { paths.insert(fields[index]) }
            index += 3
        }
        return paths
    }
}
