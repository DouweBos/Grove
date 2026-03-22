// GitKit/Parsers/BlameParser.swift
// Grove
//
// Parses the output of `git blame --porcelain` into [BlameEntry] values.
//
// Porcelain blame format:
//   <40-char SHA> <orig-line> <final-line> <num-lines>   — commit header
//   author <name>
//   author-mail <email>
//   author-time <unix-timestamp>
//   author-tz <timezone>
//   committer <name>
//   committer-mail <email>
//   committer-time <unix-timestamp>
//   committer-tz <timezone>
//   summary <text>
//   [previous <sha> <filename>]
//   filename <path>
//   \t<line content>                                     — line content (tab-prefixed)

import Foundation

// MARK: - BlameParser

/// Parses `git blame --porcelain` output into ``BlameEntry`` values.
enum BlameParser {

    // MARK: Public API

    /// Parse the stdout of `git blame --porcelain <file>`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of blame entries, each covering one contiguous block of lines
    ///            sharing the same commit.
    nonisolated static func parse(_ output: String) -> [BlameEntry] {
        guard !output.isEmpty else { return [] }

        let lines = output.components(separatedBy: "\n")
        var i = 0

        // Accumulate per-SHA metadata across multiple blame blocks.
        var commitCache: [String: CommitMeta] = [:]
        var rawEntries: [RawEntry] = []

        while i < lines.count {
            let line = lines[i]

            // A commit header line is 40 hex chars followed by three integers.
            guard isCommitHeader(line) else { i += 1; continue }

            let headerParts = line.components(separatedBy: " ")
            guard headerParts.count >= 4,
                  let origLine  = Int(headerParts[1]),
                  let finalLine = Int(headerParts[2]),
                  let numLines  = Int(headerParts[3]) else {
                i += 1; continue
            }

            let sha = headerParts[0]
            i += 1

            // Read metadata lines until we hit the tab-prefixed content line.
            var meta = commitCache[sha] ?? CommitMeta()
            var filename: String?

            while i < lines.count {
                let metaLine = lines[i]
                if metaLine.hasPrefix("\t") {
                    // This is the content line; consumed but not stored.
                    i += 1
                    break
                }
                parseMetaLine(metaLine, into: &meta, filename: &filename)
                i += 1
            }

            commitCache[sha] = meta

            rawEntries.append(RawEntry(
                sha: sha,
                finalLine: finalLine,
                origLine: origLine,
                numLines: numLines,
                filename: filename,
                meta: meta
            ))
        }

        // Collapse adjacent entries with the same SHA into single BlameEntry blocks.
        return collapseEntries(rawEntries)
    }

    // MARK: Private Types

    private struct CommitMeta {
        var authorName: String = ""
        var authorEmail: String = ""
        var authorTime: Date   = Date(timeIntervalSince1970: 0)
        var summary: String = ""
        var originalPath: String?
    }

    private struct RawEntry {
        let sha: String
        let finalLine: Int
        let origLine: Int
        let numLines: Int
        let filename: String?
        let meta: CommitMeta
    }

    // MARK: Parsing Helpers

    nonisolated private static func isCommitHeader(_ line: String) -> Bool {
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 4 else { return false }
        let sha = parts[0]
        guard sha.count == 40 else { return false }
        return sha.allSatisfy(\.isHexDigit)
    }

    nonisolated private static func parseMetaLine(
        _ line: String,
        into meta: inout CommitMeta,
        filename: inout String?
    ) {
        if line.hasPrefix("author ") && !line.hasPrefix("author-") {
            meta.authorName = String(line.dropFirst("author ".count))
        } else if line.hasPrefix("author-mail ") {
            let raw = String(line.dropFirst("author-mail ".count))
            meta.authorEmail = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        } else if line.hasPrefix("author-time ") {
            let ts = String(line.dropFirst("author-time ".count))
            if let interval = TimeInterval(ts) {
                meta.authorTime = Date(timeIntervalSince1970: interval)
            }
        } else if line.hasPrefix("summary ") {
            meta.summary = String(line.dropFirst("summary ".count))
        } else if line.hasPrefix("filename ") {
            filename = String(line.dropFirst("filename ".count))
            if meta.originalPath == nil {
                meta.originalPath = filename
            }
        } else if line.hasPrefix("previous ") {
            // `previous <sha> <filename>` — tracks renames.
            let parts = line.components(separatedBy: " ")
            if parts.count >= 3 {
                meta.originalPath = parts.dropFirst(2).joined(separator: " ")
            }
        }
    }

    // MARK: Collapsing

    nonisolated private static func collapseEntries(_ raw: [RawEntry]) -> [BlameEntry] {
        // Group consecutive lines from the same commit into one BlameEntry.
        var result: [BlameEntry] = []

        var idx = 0
        while idx < raw.count {
            let first = raw[idx]
            let start = first.finalLine
            var count = first.numLines

            // Look ahead for consecutive blocks from the same SHA.
            var next = idx + 1
            while next < raw.count && raw[next].sha == first.sha {
                let nextEntry = raw[next]
                count += nextEntry.numLines
                next += 1
            }

            let entryID = "\(first.sha)-\(start)"
            result.append(BlameEntry(
                id: entryID,
                lineStart: start,
                lineCount: count,
                commitSHA: first.sha,
                authorName: first.meta.authorName,
                authorEmail: first.meta.authorEmail,
                authorDate: first.meta.authorTime,
                summary: first.meta.summary,
                originalPath: first.meta.originalPath
            ))

            idx = next
        }

        return result
    }
}
