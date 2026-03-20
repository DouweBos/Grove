// GitKit/Parsers/ReflogParser.swift
// Grove
//
// Parses the output of `git reflog` with a custom format into [ReflogEntry].
//
// Format string used by GitRepository:
//   %H%x00%gD%x00%gs%x00%an%x00%ae%x00%aI%x00%x01
//   (followed by reading the previous SHA from gd)
//
// We use a simpler two-pass approach:
//   git reflog --format="%H%x00%P%x00%gs%x00%an%x00%ae%x00%aI%x00%x01"
//
// Fields (NUL-separated):
//   0  %H   — new (destination) SHA
//   1  %P   — parent SHA(s) — we use first parent as "oldSHA"
//   2  %gs  — reflog subject / action message
//   3  %an  — committer name
//   4  %ae  — committer email
//   5  %aI  — date ISO 8601

import Foundation

// MARK: - ReflogParser

/// Parses `git reflog` output into ``ReflogEntry`` values.
enum ReflogParser {

    // MARK: Constants

    /// Format string for `git reflog`.
    nonisolated static var formatString: String {
        "%H%x00%P%x00%gs%x00%an%x00%ae%x00%aI%x00%x01"
    }

    // MARK: Public API

    /// Parse the stdout of `git reflog --format=<formatString>`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of reflog entries, newest first.
    nonisolated static func parse(_ output: String) -> [ReflogEntry] {
        guard !output.isEmpty else { return [] }

        return output
            .components(separatedBy: "\u{01}")
            .compactMap { parseRecord($0) }
    }

    // MARK: Record Parsing

    nonisolated private static func parseRecord(_ record: String) -> ReflogEntry? {
        let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "\0")
        guard fields.count >= 6 else { return nil }

        let newSHA         = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let parentsStr     = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let message        = fields[2]
        let committerName  = fields[3]
        let committerEmail = fields[4]
        let dateStr        = fields[5]

        guard newSHA.count == 40 else { return nil }
        guard let date = parseISO8601(dateStr) else { return nil }

        // Use the first parent SHA as "oldSHA"; fall back to zeroed SHA if root commit.
        let oldSHA = parentsStr.components(separatedBy: " ").first ?? String(repeating: "0", count: 40)

        return ReflogEntry(
            id:             "\(newSHA)-\(message.hashValue)",
            oldSHA:         oldSHA.isEmpty ? String(repeating: "0", count: 40) : oldSHA,
            newSHA:         newSHA,
            committerName:  committerName,
            committerEmail: committerEmail,
            date:           date,
            message:        message
        )
    }

    // MARK: Date Parsing

    nonisolated private static func parseISO8601(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
