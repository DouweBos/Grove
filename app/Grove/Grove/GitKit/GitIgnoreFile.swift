// GitKit/GitIgnoreFile.swift
// Grove
//
// Builds gitignore patterns for files, extensions and folders, and appends them to an ignore file.

import Foundation

enum GitIgnoreFile {

    /// Anchored to the repository root so a file of the same name elsewhere stays visible.
    static func pattern(forFile path: String) -> String {
        "/" + escape(path)
    }

    static func pattern(forExtension ext: String) -> String {
        "*." + escape(ext)
    }

    /// `directory` is repository-relative, with or without a trailing slash.
    static func pattern(forFolder directory: String) -> String {
        let trimmed = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return "/" + escape(trimmed) + "/"
    }

    /// `existing` with the patterns it doesn't already contain appended, one per line.
    static func appending(_ patterns: [String], to existing: String) -> String {
        let present = Set(existing.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        var seen = Set<String>()
        let added = patterns.filter { !present.contains($0) && seen.insert($0).inserted }
        guard !added.isEmpty else { return existing }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        return existing + separator + added.joined(separator: "\n") + "\n"
    }

    static func append(_ patterns: [String], to file: URL) throws {
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let updated = appending(patterns, to: existing)
        guard updated != existing else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Glob characters, a leading `#` or `!` and trailing spaces would otherwise change what the line matches.
    static func escape(_ text: String) -> String {
        var result = ""
        for char in text {
            if "*?[\\".contains(char) { result.append("\\") }
            result.append(char)
        }
        if let first = result.first, first == "#" || first == "!" { result.insert("\\", at: result.startIndex) }
        var trailing = 0
        while result.dropLast(trailing).last == " " { trailing += 1 }
        if trailing > 0 {
            result = String(result.dropLast(trailing)) + String(repeating: "\\ ", count: trailing)
        }
        return result
    }
}
