// Engine/Parsers/DiffParser.swift
// GroveKit
//
// Parses unified diff output (from `git diff` or `git show`) into
// [DiffResult] values composed of HunkData and DiffLine.
//
// Unified diff reference:
//   https://www.gnu.org/software/diffutils/manual/html_node/Unified-Format.html

import CryptoKit
import Foundation

// MARK: - DiffParser

/// Parses unified diff output into ``DiffResult`` values.
///
/// Handles output from:
/// - `git diff`
/// - `git diff --cached`
/// - `git show <sha>`
/// - `git diff <sha>^! -- <path>` (single-commit diff)
public enum DiffParser {

    // MARK: Public API

    /// Parse the stdout of a `git diff` command.
    ///
    /// - Parameter output: Raw unified diff string.
    /// - Returns: One ``DiffResult`` per changed file.
    public nonisolated static func parse(_ output: String) -> [DiffResult] {
        guard !output.isEmpty else { return [] }

        var results: [DiffResult] = []
        // Split into per-file sections at "diff --git" boundaries.
        // On bytes: as Characters "\r\n" is one, and "+" joins a combining mark after it.
        let lines = output.utf8.split(separator: 0x0A, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var i = 0

        while i < lines.count {
            if lines[i].hasPrefix("diff --git ") {
                if let (result, next) = parseFileDiff(lines: lines, startIndex: i) {
                    results.append(result)
                    i = next
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }

        return results
    }

    /// A patch's files with their status, read from `git diff --name-status` output when given and
    /// otherwise inferred from the hunks (e.g. for a code host's pull request diff).
    public nonisolated static func fileDiffs(patch: String, nameStatus: String? = nil) -> [FileDiff] {
        var statuses: [String: FileStatus] = [:]
        for line in (nameStatus ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2, let code = parts[0].first,
                  let status = FileStatus(rawValue: String(code)) else { continue }
            statuses[GitPathQuoting.unquote(parts[parts.count - 1])] = status
        }
        return parse(patch).map { diff in
            FileDiff(path: diff.filePath, status: statuses[diff.filePath] ?? inferStatus(diff),
                     diff: diff, stats: diff.stats)
        }
    }

    nonisolated static func inferStatus(_ diff: DiffResult) -> FileStatus {
        if diff.oldPath != nil { return .renamed }
        if let hunk = diff.hunks.first, diff.hunks.count == 1 {
            if hunk.oldStart == 0 && hunk.oldCount == 0 { return .added }
            if hunk.newStart == 0 && hunk.newCount == 0 { return .deleted }
        }
        return .modified
    }

    /// Parse a unified diff for a single file, starting from a `diff --git` line.
    ///
    /// - Returns: A `(DiffResult, nextLineIndex)` tuple, or `nil` on failure.
    nonisolated static func parseSingleFile(_ output: String) -> DiffResult? {
        parse(output).first
    }

    // MARK: File-Level Parsing

    nonisolated private static func parseFileDiff(
        lines: [String],
        startIndex: Int
    ) -> (DiffResult, Int)? {
        var i = startIndex
        guard lines[i].hasPrefix("diff --git ") else { return nil }

        // Extract paths from the diff --git header.
        // Format: `diff --git a/path b/path`
        let diffHeader = lines[i]
        let (filePath, oldPath) = extractPaths(from: diffHeader)
        i += 1

        var isBinary = false
        var change = FileChange.content
        var newFilePath = filePath
        var renamedOldPath: String? = oldPath != filePath ? oldPath : nil

        // Consume extended header lines (index, mode, rename, binary, etc.)
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("diff --git ") { break }
            if line.hasPrefix("--- ") || line.hasPrefix("+++ ") || line.hasPrefix("@@ ") { break }

            if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") {
                isBinary = true
            }
            if line.hasPrefix("new file mode ") {
                change = .added(mode: String(line.dropFirst("new file mode ".count)))
            }
            if line.hasPrefix("deleted file mode ") {
                change = .deleted(mode: String(line.dropFirst("deleted file mode ".count)))
            }
            if line.hasPrefix("rename to ") {
                newFilePath = GitPathQuoting.unquote(String(line.dropFirst("rename to ".count)))
                change = .renamed
            }
            if line.hasPrefix("rename from ") {
                renamedOldPath = GitPathQuoting.unquote(String(line.dropFirst("rename from ".count)))
            }
            i += 1
        }

        // Skip `---` and `+++` header lines if not yet consumed.
        while i < lines.count && (lines[i].hasPrefix("--- ") || lines[i].hasPrefix("+++ ")) {
            if let path = headerPath(lines[i], marker: "+++ ", side: "b/") {
                newFilePath = path
            }
            i += 1
        }
        let identity = "\(change)\n\(renamedOldPath ?? "")\n\(newFilePath)\n"

        // Parse hunks.
        var hunks: [HunkData] = []
        var additions = 0
        var deletions = 0

        while i < lines.count && !lines[i].hasPrefix("diff --git ") {
            if lines[i].hasPrefix("@@ ") {
                if let (hunk, next) = parseHunk(lines: lines, startIndex: i, file: identity) {
                    additions += hunk.lines.filter { $0.type == .addition }.count
                    deletions += hunk.lines.filter { $0.type == .deletion }.count
                    hunks.append(hunk)
                    i = next
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }

        var result = DiffResult(
            filePath: newFilePath,
            oldPath: renamedOldPath,
            isBinary: isBinary,
            hunks: hunks,
            stats: DiffStats(additions: additions, deletions: deletions)
        )

        result.change = change
        return (result, i)
    }

    // MARK: Hunk Parsing

    /// Parse a single hunk starting from its `@@ -old,count +new,count @@` line.
    ///
    /// - Returns: A `(HunkData, nextLineIndex)` tuple, or `nil` on parse failure.
    nonisolated private static func parseHunk(
        lines: [String],
        startIndex: Int,
        file: String
    ) -> (HunkData, Int)? {
        let headerLine = lines[startIndex]
        guard headerLine.hasPrefix("@@ ") else { return nil }

        guard let (oldStart, oldCount, newStart, newCount) = parseHunkHeader(headerLine) else {
            return nil
        }

        var end = startIndex + 1
        while end < lines.count, !lines[end].hasPrefix("@@ "), !lines[end].hasPrefix("diff --git ") { end += 1 }
        let next = end
        // The output's trailing newline leaves an empty last element; it is not a context line.
        if end == lines.count, end > startIndex + 1, lines[end - 1].isEmpty { end -= 1 }

        let hunkID = hunkID(file: file, lines: lines[startIndex..<end])
        var diffLines: [DiffLine] = []
        var oldLine = oldStart
        var newLine = newStart

        for line in lines[(startIndex + 1)..<end] {
            let marker = line.utf8.first
            if marker == UInt8(ascii: "\\") {
                // `\ No newline at end of file` belongs to the line above it.
                if !diffLines.isEmpty { diffLines[diffLines.count - 1].endsWithoutNewline = true }
                continue
            }

            let lineType: DiffLineType = switch marker {
            case UInt8(ascii: "+"): .addition
            case UInt8(ascii: "-"): .deletion
            default: .context
            }
            // An empty context line may come without its leading space (diff.suppressBlankEmpty).
            let hasPrefix = lineType != .context || marker == UInt8(ascii: " ")
            let content = hasPrefix ? String(decoding: line.utf8.dropFirst(), as: UTF8.self) : line
            let lineID = "\(hunkID)-\(diffLines.count)"
            let diffLine: DiffLine

            switch lineType {
            case .addition:
                diffLine = DiffLine(id: lineID, type: .addition, content: content,
                                    oldLineNumber: nil, newLineNumber: newLine)
                newLine += 1
            case .deletion:
                diffLine = DiffLine(id: lineID, type: .deletion, content: content,
                                    oldLineNumber: oldLine, newLineNumber: nil)
                oldLine += 1
            case .context:
                diffLine = DiffLine(id: lineID, type: .context, content: content,
                                    oldLineNumber: oldLine, newLineNumber: newLine)
                oldLine += 1
                newLine += 1
            }

            diffLines.append(diffLine)
        }

        let hunk = HunkData(
            id: hunkID,
            header: headerLine,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: diffLines
        )

        return (hunk, next)
    }

    /// Covers the file's change and every byte of the hunk, so an id never outlives what it showed.
    nonisolated private static func hunkID(file: String, lines: ArraySlice<String>) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(file.utf8))
        for line in lines {
            hasher.update(data: Data(line.utf8))
            hasher.update(data: Data([0x0A]))
        }
        return hasher.finalize().prefix(16).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    // MARK: Header Parsing Helpers

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@ ...` into component integers.
    nonisolated private static func parseHunkHeader(
        _ header: String
    // swiftlint:disable:next large_tuple
    ) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        // Match the `@@ -a,b +c,d @@` portion.
        guard let atRange = header.range(of: "@@"),
              let closeRange = header.range(of: " @@", range: atRange.upperBound..<header.endIndex) else {
            return nil
        }

        let inner = String(header[atRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        // inner looks like `-10,6 +10,8`
        let halves = inner.components(separatedBy: " ")
        guard halves.count >= 2 else { return nil }

        let oldPart = halves[0].hasPrefix("-") ? String(halves[0].dropFirst()) : halves[0]
        let newPart = halves[1].hasPrefix("+") ? String(halves[1].dropFirst()) : halves[1]

        let oldComponents = oldPart.components(separatedBy: ",")
        let newComponents = newPart.components(separatedBy: ",")

        guard let oldStart = Int(oldComponents[0]) else { return nil }
        let oldCount = oldComponents.count > 1 ? (Int(oldComponents[1]) ?? 1) : 1

        guard let newStart = Int(newComponents[0]) else { return nil }
        let newCount = newComponents.count > 1 ? (Int(newComponents[1]) ?? 1) : 1

        return (oldStart, oldCount, newStart, newCount)
    }

    /// The path of a `--- a/…` or `+++ b/…` line, or nil for another kind of name.
    nonisolated private static func headerPath(_ line: String, marker: String, side: String) -> String? {
        guard line.hasPrefix(marker) else { return nil }
        var field = String(line.dropFirst(marker.count))
        // git ends names containing spaces with a tab.
        if field.hasSuffix("\t") { field.removeLast() }
        let name = GitPathQuoting.unquote(field)
        return name.hasPrefix(side) ? String(name.dropFirst(side.count)) : nil
    }

    /// Extract the destination and source file paths from a `diff --git a/... b/...` line.
    nonisolated private static func extractPaths(from diffLine: String) -> (filePath: String, oldPath: String) {
        // Format: `diff --git a/path/to/file b/path/to/file`, either name possibly quoted.
        let names = String(diffLine.dropFirst("diff --git ".count))
        if let old = GitPathQuoting.leadingToken(of: names) {
            let new = GitPathQuoting.unquote(String(old.rest.dropFirst()))
            return (String(new.dropFirst(2)), String(old.path.dropFirst(2)))
        }
        guard names.hasPrefix("a/") else { return (diffLine, diffLine) }

        let rest = String(names.dropFirst(2))
        // Without a rename both names are the same, which settles paths that contain ` b/`.
        let half = rest.prefix(max(0, (rest.count - 3) / 2))
        if rest == "\(half) b/\(half)" { return (String(half), String(half)) }
        if let separatorRange = rest.range(of: " \"b/", options: .backwards) {
            let new = GitPathQuoting.unquote(String(rest[rest.index(after: separatorRange.lowerBound)...]))
            return (String(new.dropFirst(2)), String(rest[..<separatorRange.lowerBound]))
        }
        // Find ` b/` — the separator between old and new path.
        if let separatorRange = rest.range(of: " b/", options: .backwards) {
            let oldPath = String(rest[rest.startIndex..<separatorRange.lowerBound])
            let newPath = String(rest[separatorRange.upperBound...])
            return (newPath, oldPath)
        }

        return (rest, rest)
    }
}
