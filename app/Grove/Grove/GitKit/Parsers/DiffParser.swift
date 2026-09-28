// GitKit/Parsers/DiffParser.swift
// Grove
//
// Parses unified diff output (from `git diff` or `git show`) into
// [DiffResult] values composed of HunkData and DiffLine.
//
// Unified diff reference:
//   https://www.gnu.org/software/diffutils/manual/html_node/Unified-Format.html

import Foundation

// MARK: - DiffParser

/// Parses unified diff output into ``DiffResult`` values.
///
/// Handles output from:
/// - `git diff`
/// - `git diff --cached`
/// - `git show <sha>`
/// - `git diff <sha>^! -- <path>` (single-commit diff)
enum DiffParser {

    // MARK: Public API

    /// Parse the stdout of a `git diff` command.
    ///
    /// - Parameter output: Raw unified diff string.
    /// - Returns: One ``DiffResult`` per changed file.
    nonisolated static func parse(_ output: String) -> [DiffResult] {
        guard !output.isEmpty else { return [] }

        var results: [DiffResult] = []
        // Split into per-file sections at "diff --git" boundaries.
        let lines = output.components(separatedBy: "\n")
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
            if line.hasPrefix("rename to ") {
                newFilePath = String(line.dropFirst("rename to ".count))
            }
            if line.hasPrefix("rename from ") {
                renamedOldPath = String(line.dropFirst("rename from ".count))
            }
            if line.hasPrefix("+++ b/") {
                newFilePath = String(line.dropFirst("+++ b/".count))
            }
            i += 1
        }

        // Skip `---` and `+++` header lines if not yet consumed.
        while i < lines.count && (lines[i].hasPrefix("--- ") || lines[i].hasPrefix("+++ ")) {
            if lines[i].hasPrefix("+++ b/") {
                newFilePath = String(lines[i].dropFirst("+++ b/".count))
            }
            i += 1
        }

        // Parse hunks.
        var hunks: [HunkData] = []
        var additions = 0
        var deletions = 0

        while i < lines.count && !lines[i].hasPrefix("diff --git ") {
            if lines[i].hasPrefix("@@ ") {
                if let (hunk, next) = parseHunk(lines: lines, startIndex: i) {
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

        let result = DiffResult(
            filePath: newFilePath,
            oldPath: renamedOldPath,
            isBinary: isBinary,
            hunks: hunks,
            stats: DiffStats(additions: additions, deletions: deletions)
        )

        return (result, i)
    }

    // MARK: Hunk Parsing

    /// Parse a single hunk starting from its `@@ -old,count +new,count @@` line.
    ///
    /// - Returns: A `(HunkData, nextLineIndex)` tuple, or `nil` on parse failure.
    nonisolated private static func parseHunk(
        lines: [String],
        startIndex: Int
    ) -> (HunkData, Int)? {
        let headerLine = lines[startIndex]
        guard headerLine.hasPrefix("@@ ") else { return nil }

        guard let (oldStart, oldCount, newStart, newCount) = parseHunkHeader(headerLine) else {
            return nil
        }

        let hunkID = "\(headerLine.hashValue)"
        var diffLines: [DiffLine] = []
        var oldLine = oldStart
        var newLine = newStart
        var i = startIndex + 1

        while i < lines.count {
            let line = lines[i]

            // Stop at next hunk or next file diff.
            if line.hasPrefix("@@ ") || line.hasPrefix("diff --git ") { break }

            // Some diffs include a `\ No newline at end of file` marker.
            if line.hasPrefix("\\ ") { i += 1; continue }

            // The output's trailing newline leaves an empty last element; it is not a context line.
            if line.isEmpty && i == lines.count - 1 { i += 1; continue }

            let lineType: DiffLineType
            let content: String

            if let first = line.first {
                switch first {
                case "+":
                    lineType = .addition
                    content = String(line.dropFirst())
                case "-":
                    lineType = .deletion
                    content = String(line.dropFirst())
                default:
                    lineType = .context
                    // Context lines start with a space; strip it.
                    content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                }
            } else {
                lineType = .context
                content = ""
            }

            let lineID = "\(hunkID)-\(i)"
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
            i += 1
        }

        let hunk = HunkData(
            id: "\(headerLine.hashValue)",
            header: headerLine,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: diffLines
        )

        return (hunk, i)
    }

    // MARK: Header Parsing Helpers

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@ ...` into component integers.
    nonisolated private static func parseHunkHeader(
        _ header: String
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

    /// Extract the destination and source file paths from a `diff --git a/... b/...` line.
    nonisolated private static func extractPaths(from diffLine: String) -> (filePath: String, oldPath: String) {
        // Format: `diff --git a/path/to/file b/path/to/file`
        // The paths may contain spaces, which makes naive splitting unreliable.
        // Strategy: strip prefix, then find the split point where ` b/` occurs.
        let prefix = "diff --git a/"
        guard diffLine.hasPrefix(prefix) else {
            return (diffLine, diffLine)
        }

        let rest = String(diffLine.dropFirst(prefix.count))
        // Find ` b/` — the separator between old and new path.
        // We look for the LAST occurrence to handle paths containing ` b/`.
        if let separatorRange = rest.range(of: " b/", options: .backwards) {
            let oldPath = String(rest[rest.startIndex..<separatorRange.lowerBound])
            let newPath = String(rest[separatorRange.upperBound...])
            return (newPath, oldPath)
        }

        return (rest, rest)
    }

    // MARK: Patch Construction

    /// Build a minimal unified diff patch from a single hunk.
    ///
    /// Used by ``GitRepository`` when applying or reversing individual hunks via
    /// `git apply --cached`.
    ///
    /// - Parameters:
    ///   - hunk: The hunk to wrap into a patch.
    ///   - filePath: Destination file path (relative to repo root).
    ///   - oldPath: Source file path; defaults to `filePath`.
    /// - Returns: A complete patch string suitable for `git apply`.
    nonisolated static func buildPatch(
        from hunk: HunkData,
        filePath: String,
        oldPath: String? = nil
    ) -> String {
        let src = oldPath ?? filePath
        var patch = ""
        patch += "diff --git a/\(src) b/\(filePath)\n"
        patch += "--- a/\(src)\n"
        patch += "+++ b/\(filePath)\n"
        patch += hunk.header + "\n"
        for line in hunk.lines {
            switch line.type {
            case .addition: patch += "+\(line.content)\n"
            case .deletion: patch += "-\(line.content)\n"
            case .context:  patch += " \(line.content)\n"
            }
        }
        return patch
    }

    /// Build a reverse patch from a hunk (for unstaging or discarding).
    ///
    /// Swaps `+` and `-` lines and adjusts the hunk header accordingly.
    nonisolated static func buildReversePatch(
        from hunk: HunkData,
        filePath: String,
        oldPath: String? = nil
    ) -> String {
        let src = oldPath ?? filePath
        // Reverse header: swap old/new line numbers.
        let reverseHeader = "@@ -\(hunk.newStart),\(hunk.newCount) +\(hunk.oldStart),\(hunk.oldCount) @@"

        var patch = ""
        patch += "diff --git a/\(src) b/\(filePath)\n"
        patch += "--- a/\(src)\n"
        patch += "+++ b/\(filePath)\n"
        patch += reverseHeader + "\n"
        for line in hunk.lines {
            switch line.type {
            case .addition: patch += "-\(line.content)\n"
            case .deletion: patch += "+\(line.content)\n"
            case .context:  patch += " \(line.content)\n"
            }
        }
        return patch
    }

    /// Build a patch from a specific subset of lines within a hunk.
    ///
    /// Lines not in `selectedLines` are converted to context lines.
    nonisolated static func buildPatch(
        from selectedLines: [DiffLine],
        in hunk: HunkData,
        filePath: String,
        oldPath: String? = nil
    ) -> String {
        let src = oldPath ?? filePath
        let selectedIDs = Set(selectedLines.map(\.id))

        // Build the effective line list: selected changes become real +/-, others become context.
        var patchLines: [(DiffLineType, String)] = []
        var newOldCount = 0
        var newNewCount = 0

        for line in hunk.lines {
            let effectiveType: DiffLineType
            let effectiveContent: String

            if selectedIDs.contains(line.id) {
                effectiveType    = line.type
                effectiveContent = line.content
            } else {
                switch line.type {
                case .addition:
                    // Unselected additions are skipped entirely (do not appear in patch).
                    continue
                case .deletion:
                    // Unselected deletions become context lines.
                    effectiveType    = .context
                    effectiveContent = line.content
                case .context:
                    effectiveType    = .context
                    effectiveContent = line.content
                }
            }

            patchLines.append((effectiveType, effectiveContent))

            switch effectiveType {
            case .addition: newNewCount += 1
            case .deletion: newOldCount += 1
            case .context:  newOldCount += 1; newNewCount += 1
            }
        }

        let header = "@@ -\(hunk.oldStart),\(newOldCount) +\(hunk.newStart),\(newNewCount) @@"

        var patch = ""
        patch += "diff --git a/\(src) b/\(filePath)\n"
        patch += "--- a/\(src)\n"
        patch += "+++ b/\(filePath)\n"
        patch += header + "\n"
        for (type, content) in patchLines {
            switch type {
            case .addition: patch += "+\(content)\n"
            case .deletion: patch += "-\(content)\n"
            case .context:  patch += " \(content)\n"
            }
        }
        return patch
    }
}
