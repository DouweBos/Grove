// Engine/Parsers/BranchParser.swift
// GroveKit
//
// Parses the output of `git for-each-ref` into [BranchInfo] values.
//
// Format string used by GitRepository:
//   %(refname)%00%(refname:short)%00%(objectname)%00%(upstream)%00%(upstream:track)%00%(HEAD)
//
// Fields (NUL-separated, one ref per line):
//   0  %(refname)            — full ref, e.g. refs/heads/main
//   1  %(refname:short)      — short name, e.g. main
//   2  %(objectname)         — full SHA the ref points at
//   3  %(upstream)           — full upstream ref, if set
//   4  %(upstream:track)— e.g. `[ahead 2]`, `[behind 1]`, `[ahead 1, behind 2]`
//   5  %(HEAD)               — `*` when this ref is HEAD, `` otherwise

import Foundation

// MARK: - BranchParser

/// Parses `git for-each-ref` output into ``BranchInfo`` values.
enum BranchParser {

    // MARK: Constants

    /// Format string for `git for-each-ref`.
    nonisolated static var formatString: String {
        "%(refname)%00%(refname:short)%00%(objectname)%00%(upstream)%00%(upstream:track)%00%(HEAD)"
    }

    // MARK: Public API

    /// Parse the stdout of `git for-each-ref --format=<formatString>`.
    ///
    /// - Parameter output: Raw stdout string from the git process.
    /// - Returns: Array of parsed branches.
    nonisolated static func parse(_ output: String) -> [BranchInfo] {
        output
            .components(separatedBy: "\n")
            .compactMap { parseLine($0) }
    }

    // MARK: Line Parsing

    nonisolated private static func parseLine(_ line: String) -> BranchInfo? {
        guard !line.isEmpty else { return nil }

        let fields = line.components(separatedBy: "\0")
        guard fields.count >= 6 else { return nil }

        let refname    = fields[0]
        let shortName  = fields[1]
        let sha        = fields[2]
        let upstream   = fields[3].isEmpty ? nil : fields[3]
        let trackShort = fields[4]
        let headMarker = fields[5]

        guard !refname.isEmpty, !sha.isEmpty else { return nil }

        let isLocal  = refname.hasPrefix("refs/heads/")
        let isRemote = refname.hasPrefix("refs/remotes/")
        // refs/remotes/<remote>/HEAD only points at the remote's default branch.
        if isRemote, refname.hasSuffix("/HEAD") { return nil }
        let isHEAD   = headMarker == "*"

        // Parse remote name from refs/remotes/<remote>/<branch>.
        var remoteName: String?
        if isRemote {
            let withoutPrefix = String(refname.dropFirst("refs/remotes/".count))
            remoteName = withoutPrefix.components(separatedBy: "/").first
        }

        let (ahead, behind) = parseTrackShort(trackShort)

        return BranchInfo(
            id: refname,
            name: shortName,
            isLocal: isLocal,
            isRemote: isRemote,
            isHEAD: isHEAD,
            targetSHA: sha,
            remoteName: remoteName,
            upstream: upstream,
            ahead: ahead,
            behind: behind
        )
    }

    // MARK: Ahead/Behind Parsing

    /// Parse `%(upstream:track)` into (ahead, behind) counts.
    ///
    /// The format is one of:
    /// - `` (empty) — no upstream configured
    /// - `[ahead N]`
    /// - `[behind N]`
    /// - `[ahead N, behind M]`
    /// - `[gone]` — upstream was deleted
    nonisolated private static func parseTrackShort(_ track: String) -> (ahead: Int, behind: Int) {
        var ahead  = 0
        var behind = 0

        if let aheadRange = track.range(of: #"ahead (\d+)"#, options: .regularExpression) {
            let match = track[aheadRange]
            if let num = match.components(separatedBy: " ").last.flatMap(Int.init) {
                ahead = num
            }
        }

        if let behindRange = track.range(of: #"behind (\d+)"#, options: .regularExpression) {
            let match = track[behindRange]
            if let num = match.components(separatedBy: " ").last.flatMap(Int.init) {
                behind = num
            }
        }

        return (ahead, behind)
    }
}
