// Engine/GitRepository+Helpers.swift
// GroveKit
//
// Shared helpers used by the GitRepository extensions.

import Foundation
import os

extension GitRepository {

    // MARK: - Helpers

    /// Load the current branch from git, returning `nil` in detached-HEAD state.
    nonisolated static func loadCurrentBranch(shell: GitShell) async throws -> BranchInfo? {
        // Check for detached HEAD first.
        let headResult = try await shell.runAllowingFailure(["symbolic-ref", "--quiet", "HEAD"])
        guard headResult.isSuccess else {
            return nil  // Detached HEAD.
        }

        let refname  = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortResult = try await shell.run(["rev-parse", "--abbrev-ref", "HEAD"])
        let shortName   = shortResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get the SHA.
        let shaResult = try await shell.run(["rev-parse", "HEAD"])
        let sha = shaResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get upstream.
        let upstreamResult = try await shell.runAllowingFailure(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
        )
        let upstream = upstreamResult.isSuccess
            ? upstreamResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        // Get ahead/behind.
        var ahead  = 0
        var behind = 0
        if let upstream {
            let abResult = try? await shell.run(
                ["rev-list", "--left-right", "--count", "HEAD...\(upstream)"]
            )
            if let abResult {
                let parts = abResult.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\t")
                ahead  = !parts.isEmpty ? (Int(parts[0]) ?? 0) : 0
                behind = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            }
        }

        return BranchInfo(
            id: refname,
            name: shortName,
            isLocal: true,
            isRemote: false,
            isHEAD: true,
            targetSHA: sha,
            remoteName: nil,
            upstream: upstream.map { "refs/remotes/\($0)" },
            ahead: ahead,
            behind: behind
        )
    }

    /// Determine the repository's current operation state.
    nonisolated static func loadRepositoryState(path: URL, runner: any GitRunner) async -> RepositoryState {
        let gitDir = path.appendingPathComponent(".git")
        func exists(_ name: String) async -> Bool { await runner.fileExists(at: gitDir.appendingPathComponent(name)) }

        // Check for in-progress operations via sentinel files/dirs.
        if await exists("MERGE_HEAD") {
            return .merge
        }
        let rebasing = await exists("rebase-merge") ? true : await exists("rebase-apply")
        if rebasing {
            // Distinguish interactive from regular rebase.
            return await exists("rebase-merge/interactive") ? .rebaseInteractive : .rebase
        }
        if await exists("REVERT_HEAD") {
            return .revert
        }
        if await exists("CHERRY_PICK_HEAD") {
            return .cherrypick
        }
        if await exists("BISECT_LOG") {
            return .bisect
        }
        return .normal
    }

    /// A fresh path in the runner's temporary directory, e.g. `grovekit-todo-<uuid>`.
    func scratchURL(_ kind: String, suffix: String = "") -> URL {
        shell.runner.temporaryDirectory.appendingPathComponent("\(naming.scratchPrefix)\(kind)-\(UUID().uuidString)\(suffix)")
    }

    /// Write `content` to a temporary executable shell script and return its URL.
    ///
    /// The caller is responsible for removing the file when done.
    func writeTemporaryScript(_ content: String) async throws -> URL {
        let url = scratchURL("script", suffix: ".sh")
        try await shell.runner.writeString(content, to: url, executable: true)
        return url
    }

    /// Removes scratch files once the caller is done; callable from \`defer\`, so it doesn't wait.
    nonisolated func discardScratch(_ urls: [URL]) {
        let runner = shell.runner
        Task { for url in urls { try? await runner.removeItem(at: url) } }
    }

    /// Wrap `string` in single quotes, escaping any embedded single quotes.
    ///
    /// Produces a POSIX shell literal safe for embedding in script bodies.
    nonisolated func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Apply a patch string via `git apply`.
    public func applyPatch(_ patch: String, cached: Bool, reverse: Bool = false) async throws {
        var args = ["apply"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args += ["--whitespace=nowarn", "-"]

        do {
            try await shell.runWithInput(args, input: patch)
        } catch GitShellError.nonZeroExit(_, _, let stderr) {
            throw GitRepositoryError.applyPatchFailed(stderr)
        }
    }

    /// Fetch branches for a given ref pattern prefix.
    func fetchBranches(refPattern: String) async throws -> [BranchInfo] {
        let result = try await shell.run([
            "for-each-ref",
            "--format=\(BranchParser.formatString)",
            refPattern
        ])
        return BranchParser.parse(result.stdout)
    }

    /// Parse `git remote -v` output into ``RemoteInfo`` values.
    nonisolated func parseRemoteVerbose(_ output: String) -> [RemoteInfo] {
        var fetchURLs: [String: String] = [:]
        var pushURLs: [String: String] = [:]

        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            // Format: `<name>\t<url> (fetch)` or `<name>\t<url> (push)`
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let name    = parts[0]
            let urlPart = parts[1]

            if urlPart.hasSuffix(" (fetch)") {
                let url = String(urlPart.dropLast(" (fetch)".count))
                fetchURLs[name] = url
            } else if urlPart.hasSuffix(" (push)") {
                let url = String(urlPart.dropLast(" (push)".count))
                pushURLs[name] = url
            }
        }

        return fetchURLs.keys.sorted().map { name in
            let fetchURL = fetchURLs[name] ?? ""
            let pushURL  = pushURLs[name]
            return RemoteInfo(
                id: name,
                name: name,
                url: fetchURL,
                pushURL: pushURL == fetchURL ? nil : pushURL
            )
        }
    }

    /// Parse `git diff --name-status` output into a path→FileStatus map.
    nonisolated func parseNameStatus(_ output: String) -> [String: FileStatus] {
        var result: [String: FileStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let statusChar = parts[0].prefix(1)
            let path       = parts.last ?? parts[1]
            let status: FileStatus
            switch statusChar {
            case "A": status = .added
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            case "T": status = .typeChange
            default:  status = .modified
            }
            result[path] = status
        }
        return result
    }

    /// Parse `git for-each-ref` tag output into ``TagInfo`` values.
    nonisolated func parseTagList(_ output: String) -> [TagInfo] {
        var result: [TagInfo] = []
        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: "\0")
            guard fields.count >= 7 else { continue }

            let name        = fields[0]
            let sha         = fields[1]
            let objectType  = fields[2]
            let derefSHA    = fields[3]
            let subject     = fields[4]
            let taggerName  = fields[5].isEmpty ? nil : fields[5]
            let taggerDateStr = fields[6]

            let isAnnotated = objectType == "tag"
            let targetSHA   = isAnnotated && !derefSHA.isEmpty ? derefSHA : sha

            let taggerDate = GitDate.parse(taggerDateStr)

            result.append(TagInfo(
                id: name,
                name: name,
                targetSHA: targetSHA,
                isAnnotated: isAnnotated,
                message: isAnnotated ? subject : nil,
                taggerName: taggerName,
                taggerDate: taggerDate
            ))
        }
        return result
    }
}
