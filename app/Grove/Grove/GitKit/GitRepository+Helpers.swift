// GitKit/GitRepository+Helpers.swift
// Grove
//
// Shared helpers used by the GitRepository extensions.

import Foundation
import os

extension GitRepository {

    // MARK: - Helpers

    /// Run a `gh` CLI subcommand in the repository's working directory.
    ///
    /// Searches for `gh` in the same well-known locations used for `git`.
    /// Throws ``GitShellError/nonZeroExit`` when the process exits non-zero.
    @discardableResult
    func ghRun(_ arguments: [String]) async throws -> ShellResult {
        let ghPath = GitRepository.resolveGhPath()
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
            do {
                let process = Process()
                process.executableURL       = URL(fileURLWithPath: ghPath)
                process.arguments           = arguments
                process.currentDirectoryURL = path
                var env = ProcessInfo.processInfo.environment
                env["LANG"]    = "en_US.UTF-8"
                env["LC_ALL"]  = "en_US.UTF-8"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                process.terminationHandler = { proc in
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout  = String(data: outData, encoding: .utf8) ?? ""
                    let stderr  = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ShellResult(stdout: stdout, stderr: stderr, exitCode: proc.terminationStatus))
                }
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.gitRepository.warning(
                "gh \(arguments.first ?? "", privacy: .public) exited \(result.exitCode, privacy: .public): \(stderr, privacy: .public)"
            )
            throw GitShellError.nonZeroExit(
                command: "gh " + (arguments.first ?? ""),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    /// Resolve the path to the `gh` CLI executable.
    nonisolated static func resolveGhPath() -> String {
        let candidates = [
            "/usr/local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/bin/gh"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "/usr/local/bin/gh"
    }

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
    nonisolated static func loadRepositoryState(path: URL) async -> RepositoryState {
        let gitDir = path.appendingPathComponent(".git")
        let fm     = FileManager.default

        // Check for in-progress operations via sentinel files/dirs.
        if fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) {
            return .merge
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path) ||
           fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path) {
            // Distinguish interactive from regular rebase.
            let interactivePath = gitDir.appendingPathComponent("rebase-merge/interactive").path
            return fm.fileExists(atPath: interactivePath) ? .rebaseInteractive : .rebase
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("REVERT_HEAD").path) {
            return .revert
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            return .cherrypick
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("BISECT_LOG").path) {
            return .bisect
        }
        return .normal
    }

    /// Write `content` to a temporary executable shell script and return its URL.
    ///
    /// The caller is responsible for removing the file when done.
    func writeTemporaryScript(_ content: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grove-\(UUID().uuidString).sh")
        try content.write(to: url, atomically: true, encoding: .utf8)
        // Make the script executable.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755 as NSNumber],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Wrap `string` in single quotes, escaping any embedded single quotes.
    ///
    /// Produces a POSIX shell literal safe for embedding in script bodies.
    nonisolated func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Apply a patch string via `git apply`.
    func applyPatch(_ patch: String, cached: Bool, reverse: Bool = false) async throws {
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
