// GitKit/Parsers/StashParser.swift
// Grove
//
// Parses the output of `git stash list` with a custom format into [StashEntry].
//
// Format string used by GitRepository:
//   %gd%x00%H%x00%gs%x00%aI
//
// Fields (NUL-separated, one stash per line):
//   0  %gd  — stash ref descriptor, e.g. `stash@{0}`
//   1  %H   — full SHA of the stash commit
//   2  %gs  — stash message (the "reflog subject")
//   3  %aI  — author date ISO 8601

import Foundation

// MARK: - StashParser

/// Parses `git stash list` output into ``StashEntry`` values.
enum StashParser {

    // MARK: Constants

    /// Format string to pass to `git stash list --format=...`.
    nonisolated static var formatString: String { "%gd%x00%H%x00%gs%x00%aI" }

    // MARK: Public API

    /// Parse the stdout of `git stash list --format=<formatString>`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of stash entries ordered by index (newest first).
    nonisolated static func parse(_ output: String) -> [StashEntry] {
        guard !output.isEmpty else { return [] }
        return output
            .components(separatedBy: "\n")
            .compactMap { parseLine($0) }
    }

    // MARK: Line Parsing

    nonisolated private static func parseLine(_ line: String) -> StashEntry? {
        guard !line.isEmpty else { return nil }

        let fields = line.components(separatedBy: "\0")
        guard fields.count >= 4 else { return nil }

        let descriptor = fields[0]   // e.g. stash@{0}
        let sha        = fields[1]
        let message    = fields[2]
        let dateStr    = fields[3]

        guard let index = parseIndex(descriptor),
              let date  = parseISO8601(dateStr) else {
            return nil
        }

        let branchName = extractBranchName(from: message)

        return StashEntry(
            id:         index,
            message:    message,
            sha:        sha,
            date:       date,
            branchName: branchName
        )
    }

    // MARK: Helpers

    /// Parse the zero-based index from `stash@{N}`.
    nonisolated private static func parseIndex(_ descriptor: String) -> Int? {
        // Match the digits inside the braces.
        guard let open  = descriptor.firstIndex(of: "{"),
              let close = descriptor.firstIndex(of: "}"),
              open < close else { return nil }
        let digits = String(descriptor[descriptor.index(after: open)..<close])
        return Int(digits)
    }

    /// Extract the branch name from a typical stash message.
    ///
    /// Standard git stash messages look like:
    /// - `WIP on main: abc123 Commit summary`
    /// - `On feature/auth: custom message`
    nonisolated private static func extractBranchName(from message: String) -> String? {
        if message.hasPrefix("WIP on ") {
            let rest = String(message.dropFirst("WIP on ".count))
            return rest.components(separatedBy: ":").first
        }
        if message.hasPrefix("On ") {
            let rest = String(message.dropFirst("On ".count))
            return rest.components(separatedBy: ":").first
        }
        return nil
    }

    nonisolated private static func parseISO8601(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f.date(from: trimmed)
    }
}
