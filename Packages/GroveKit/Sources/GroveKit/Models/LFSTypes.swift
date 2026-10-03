// Models/LFSTypes.swift
// GroveKit
//
// Git LFS state of a repository and the pointer files LFS stores in git.

import Foundation

/// Whether a repository uses Git LFS and whether git-lfs can run for it.
public struct LFSStatus: Equatable, Sendable {
    var usesLFS = false
    var isInstalled = true

    /// LFS files stay pointers and checkouts of them fail until git-lfs is installed.
    public var isMissing: Bool { usesLFS && !isInstalled }

    public static let missingMessage = "This repository uses Git LFS, but git-lfs isn't installed, so LFS files show as pointers "
        + "and pulls that touch them fail. Install it with \u{201C}brew install git-lfs\u{201D}, then run \u{201C}git lfs install\u{201D}."
}

/// The small text file git stores in place of an LFS object.
public struct LFSPointer: Equatable, Sendable {
    static let versionPrefix = "version https://git-lfs.github.com/spec/"

    public let oid: String
    public let size: Int64

    public var shortOID: String { String(oid.prefix(12)) }

    public init(oid: String, size: Int64) {
        self.oid = oid
        self.size = size
    }

    public init?(lines: [String]) {
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
    public init?(data: Data) {
        guard data.count < 1024, let text = String(data: data, encoding: .utf8) else { return nil }
        self.init(lines: text.split(separator: "\n").map(String.init))
    }

    /// The old and new pointer when `diff` is a change to an LFS pointer file, nil for ordinary diffs.
    public static func sides(of diff: DiffResult) -> (old: LFSPointer?, new: LFSPointer?)? {
        let lines = diff.hunks.flatMap(\.lines)
        let old = LFSPointer(lines: lines.filter { $0.type != .addition }.map(\.content))
        let new = LFSPointer(lines: lines.filter { $0.type != .deletion }.map(\.content))
        guard old != nil || new != nil else { return nil }
        return (old, new)
    }
}
