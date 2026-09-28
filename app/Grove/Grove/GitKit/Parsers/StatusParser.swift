// GitKit/Parsers/StatusParser.swift
// Grove
//
// Parses the output of `git status --porcelain=v2 -uall` into [StatusEntry].
//
// Porcelain v2 format reference:
//   https://git-scm.com/docs/git-status#_porcelain_format_version_2
//
// Line types:
//   `1 XY sub mH mI mW hH hI path`          — ordinary changed entry
//   `2 XY sub mH mI mW hH hI X score path\torigPath` — renamed/copied
//   `u XY sub m1 m2 m3 mW h1 h2 h3 path`    — unmerged (conflict)
//   `? path`                                  — untracked
//   `! path`                                  — ignored

import Foundation

// MARK: - StatusParser

/// Parses `git status --porcelain=v2` output into ``StatusEntry`` values.
enum StatusParser {

    // MARK: Public API

    /// Parse the stdout of `git status --porcelain=v2 -uall`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of parsed status entries.
    nonisolated static func parse(_ output: String) -> [StatusEntry] {
        output
            .components(separatedBy: "\n")
            .compactMap { parseLine($0) }
    }

    // MARK: Line Dispatch

    nonisolated private static func parseLine(_ line: String) -> StatusEntry? {
        guard !line.isEmpty else { return nil }

        switch line.first {
        case "1": return parseOrdinary(line)
        case "2": return parseRenamedCopied(line)
        case "u": return parseUnmerged(line)
        case "?": return parseUntracked(line, status: .untracked)
        case "!": return parseUntracked(line, status: .ignored)
        default:  return nil
        }
    }

    // MARK: Ordinary Changes  (`1 XY ...`)

    // Format: `1 XY sub mH mI mW hH hI path`
    nonisolated private static func parseOrdinary(_ line: String) -> StatusEntry? {
        // Split on spaces, but path may contain spaces — take fields 0..8, rest is path.
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 9, parts[0] == "1" else { return nil }

        let xy   = parts[1]
        let path = parts[8...].joined(separator: " ")

        let indexStatus  = fileStatus(from: xy.first)
        let workdirStatus = fileStatus(from: xy.dropFirst().first)

        return StatusEntry(id: path, path: path, indexStatus: indexStatus, workdirStatus: workdirStatus)
    }

    // MARK: Renamed / Copied  (`2 XY ...`)

    // Format: `2 XY sub mH mI mW hH hI X score path\torigPath`
    nonisolated private static func parseRenamedCopied(_ line: String) -> StatusEntry? {
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 10, parts[0] == "2" else { return nil }

        let xy    = parts[1]
        // Fields 9..end contain "path\torigPath"
        let pathField = parts[9...].joined(separator: " ")
        // The destination path comes before the tab.
        let path  = pathField.components(separatedBy: "\t").first ?? pathField

        let indexStatus  = fileStatus(from: xy.first)
        let workdirStatus = fileStatus(from: xy.dropFirst().first)

        return StatusEntry(id: path, path: path, indexStatus: indexStatus, workdirStatus: workdirStatus)
    }

    // MARK: Unmerged  (`u XY ...`)

    // Format: `u XY sub m1 m2 m3 mW h1 h2 h3 path`
    nonisolated private static func parseUnmerged(_ line: String) -> StatusEntry? {
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 11, parts[0] == "u" else { return nil }

        let path = parts[10...].joined(separator: " ")

        // Both index and workdir are treated as conflicted for unmerged entries.
        return StatusEntry(id: path, path: path, indexStatus: .conflicted, workdirStatus: .conflicted)
    }

    // MARK: Untracked / Ignored  (`? path` or `! path`)

    nonisolated private static func parseUntracked(_ line: String, status: FileStatus) -> StatusEntry? {
        guard line.count > 2 else { return nil }
        let path = String(line.dropFirst(2))
        guard !path.isEmpty else { return nil }
        return StatusEntry(id: path, path: path, indexStatus: .unmodified, workdirStatus: status)
    }

    // MARK: FileStatus Mapping

    /// Map a single porcelain v2 XY character to ``FileStatus``.
    nonisolated private static func fileStatus(from char: Character?) -> FileStatus {
        guard let char else { return .unmodified }
        switch char {
        case ".": return .unmodified
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "U": return .conflicted
        case "T": return .typeChange
        case "?": return .untracked
        case "!": return .ignored
        default:  return .unmodified
        }
    }
}
