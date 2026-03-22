// GitKit/Parsers/LogParser.swift
// Grove
//
// Parses the output of `git log` with a null-delimited custom format
// into [CommitInfo] values.
//
// The format string used by GitRepository:
//   %H%x00%s%x00%b%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%P%x00%G?%x00
//
// Fields (null-separated):
//   0  %H   — full SHA
//   1  %s   — subject (summary)
//   2  %b   — body
//   3  %an  — author name
//   4  %ae  — author email
//   5  %aI  — author date ISO 8601
//   6  %cn  — committer name
//   7  %ce  — committer email
//   8  %cI  — committer date ISO 8601
//   9  %P   — space-separated parent SHAs
//   10 %G?  — signature verification status (G=good, B=bad, N=no signature, etc.)

import Foundation

// MARK: - LogParser

/// Parses `git log` output into ``CommitInfo`` values.
enum LogParser {

    // MARK: Constants

    /// The format string to pass to `git log --format=...`.
    ///
    /// Fields are separated by NUL (`%x00`) to handle multi-line bodies.
    /// A record separator (`%x01`) ends each commit record.
    nonisolated static var formatString: String {
        "%H%x00%s%x00%b%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%P%x00%G?%x00%x01"
    }

    // MARK: Public API

    /// Parse the stdout of `git log --format=<formatString>`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of parsed commits in the order git produced them.
    nonisolated static func parse(_ output: String) -> [CommitInfo] {
        guard !output.isEmpty else { return [] }

        // Split on the record separator (U+0001).
        let records = output.components(separatedBy: "\u{01}")
        return records.compactMap { parseRecord($0) }
    }

    // MARK: Record Parsing

    nonisolated private static func parseRecord(_ record: String) -> CommitInfo? {
        // Each record is NUL-separated fields.
        let fields = record
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\0")

        // Need at least 11 fields.
        guard fields.count >= 11 else { return nil }

        let sha            = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard sha.count == 40 else { return nil }

        let summary        = fields[1]
        let body           = fields[2].isEmpty ? nil : fields[2]
        let authorName     = fields[3]
        let authorEmail    = fields[4]
        let authorDateStr  = fields[5]
        let committerName  = fields[6]
        let committerEmail = fields[7]
        let committerDate  = fields[8]
        let parentsStr     = fields[9]
        let signatureStatus = fields[10]

        guard let authorDate     = parseISO8601(authorDateStr),
              let committerDateV = parseISO8601(committerDate) else {
            return nil
        }

        let parentIDs = parentsStr
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let isSigned = signatureStatus == "G" || signatureStatus == "U" || signatureStatus == "E"

        let fullMessage: String
        if let body, !body.isEmpty {
            fullMessage = "\(summary)\n\n\(body)"
        } else {
            fullMessage = summary
        }

        return CommitInfo(
            id: sha,
            message: fullMessage,
            summary: summary,
            body: body,
            authorName: authorName,
            authorEmail: authorEmail,
            authorDate: authorDate,
            committerName: committerName,
            committerEmail: committerEmail,
            committerDate: committerDateV,
            parentIDs: parentIDs,
            isSigned: isSigned
        )
    }

    // MARK: Date Parsing

    nonisolated private static func parseISO8601(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Create formatters locally to avoid actor-isolation issues on static state.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) { return date }
        return nil
    }
}
