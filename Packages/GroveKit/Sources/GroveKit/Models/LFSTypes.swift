// Models/LFSTypes.swift
// GroveKit
//
// Git LFS state of a repository and the pointer files LFS stores in git.

import Foundation

/// Whether a repository uses Git LFS and whether git-lfs can run for it.
struct LFSStatus: Equatable, Sendable {
    var usesLFS = false
    var isInstalled = true

    /// LFS files stay pointers and checkouts of them fail until git-lfs is installed.
    var isMissing: Bool { usesLFS && !isInstalled }

    static let missingMessage = "This repository uses Git LFS, but git-lfs isn't installed, so LFS files show as pointers "
        + "and pulls that touch them fail. Install it with \u{201C}brew install git-lfs\u{201D}, then run \u{201C}git lfs install\u{201D}."
}

/// The small text file git stores in place of an LFS object.
struct LFSPointer: Equatable, Sendable {
    static let versionPrefix = "version https://git-lfs.github.com/spec/"

    let oid: String
    let size: Int64

    var shortOID: String { String(oid.prefix(12)) }

    init(oid: String, size: Int64) {
        self.oid = oid
        self.size = size
    }

    init?(lines: [String]) {
        guard lines.first?.hasPrefix(Self.versionPrefix) == true else { return nil }
        var oid: String?
        var size: Int64?
        for line in lines.dropFirst() {
            if line.hasPrefix("oid sha256:") { oid = String(line.dropFirst("oid sha256:".count)) }
            if line.hasPrefix("size ") { size = Int64(line.dropFirst("size ".count)) }
        }
        guard let oid, let size else { return nil }
        self.init(oid: oid, size: size)
    }

    /// Pointers are under 200 bytes; anything larger is real content.
    init?(data: Data) {
        guard data.count < 1024, let text = String(data: data, encoding: .utf8) else { return nil }
        self.init(lines: text.split(separator: "\n").map(String.init))
    }

    /// The old and new pointer when `diff` is a change to an LFS pointer file, nil for ordinary diffs.
    static func sides(of diff: DiffResult) -> (old: LFSPointer?, new: LFSPointer?)? {
        let lines = diff.hunks.flatMap(\.lines)
        let old = LFSPointer(lines: lines.filter { $0.type != .addition }.map(\.content))
        let new = LFSPointer(lines: lines.filter { $0.type != .deletion }.map(\.content))
        guard old != nil || new != nil else { return nil }
        return (old, new)
    }
}
