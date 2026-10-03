// Engine/GitErrorMessage.swift
// GroveKit
//
// Turns git's stderr into a message for people: known failures get a plain explanation,
// anything else is stripped of hints, progress and prefixes.

import Foundation

nonisolated enum GitErrorMessage {

    static func message(command: String, stderr: String) -> String {
        if let known = known(stderr) { return known }
        let cleaned = clean(stderr)
        return cleaned.isEmpty ? "git \(command) failed." : cleaned
    }

    private static func known(_ stderr: String) -> String? {
        let text = stderr.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

        if has("stale info") {
            return "Someone pushed to the remote branch since your last fetch. Fetch, check their commits, then push again."
        }
        if has("gh006", "protected branch") {
            return "The remote doesn't allow pushing to this protected branch. Push to another branch and open a pull request."
        }
        if has("(fetch first)", "(non-fast-forward)", "tip of your current branch is behind") {
            return "The remote has commits you don't have yet. Pull them first, then push again."
        }
        if has("tag already exists") {
            return "A tag with this name already exists on the remote."
        }
        if has("need to specify how to reconcile divergent branches", "not possible to fast-forward") {
            return "Your branch and the remote have both moved on. Pull with merge or rebase to combine them."
        }
        if has("local changes to the following files would be overwritten") {
            return "Your uncommitted changes would be overwritten\(fileList(in: stderr)). Commit or stash them first."
        }
        if has("untracked working tree files would be overwritten", "untracked working tree files would be removed") {
            return "Untracked files would be overwritten\(fileList(in: stderr)). Move or delete them first."
        }
        if has("automatic merge failed", "could not apply", "conflict (") {
            return "There are conflicts to resolve. Fix the conflicted files, then continue."
        }
        if has("index.lock") {
            return "Another git process is using this repository. If none is running, delete .git/index.lock."
        }
        if has("authentication failed", "could not read username", "could not read password",
               "permission denied (publickey", "invalid username or password") {
            return "The remote didn't accept your credentials. Check your account or SSH key for this host."
        }
        if has("repository not found", "does not appear to be a git repository")
            || text.contains("repository '") && text.contains("' not found") {
            return "The remote repository wasn't found, or you don't have access to it."
        }
        if has("could not resolve host", "failed to connect", "connection timed out", "network is unreachable") {
            return "Couldn't reach the remote. Check your internet connection."
        }
        return nil
    }

    /// Drops hints, progress and ref summaries, and git's `error:`/`fatal:` prefixes.
    static func clean(_ stderr: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("hint:") || line.hasPrefix("To ") || line.hasPrefix("From ") || line.hasPrefix("!")
                || line.hasPrefix("Cloning into") || line.contains("% (") || isTransferProgress(line) { return nil }
            for prefix in ["remote: ", "error: ", "fatal: "] where line.hasPrefix(prefix) {
                line.removeFirst(prefix.count)
            }
            return line.isEmpty || line == "remote:" ? nil : line
        }
        guard let first = lines.first else { return "" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + lines.dropFirst()).joined(separator: "\n")
    }

    private static func isTransferProgress(_ line: String) -> Bool {
        ["Enumerating objects", "Counting objects", "Compressing objects", "Total "]
            .contains { line.hasPrefix("remote: " + $0) || line.hasPrefix($0) }
    }

    /// ": a, b" from the tab-indented paths git lists under "would be overwritten", or "" when there are none.
    private static func fileList(in stderr: String) -> String {
        let files = stderr.split(separator: "\n").filter { $0.hasPrefix("\t") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !files.isEmpty else { return "" }
        let shown = files.prefix(3).joined(separator: ", ")
        return ": " + shown + (files.count > 3 ? " and \(files.count - 3) more" : "")
    }
}
