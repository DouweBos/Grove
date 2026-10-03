// Models/SVNTypes.swift
// GroveKit
//
// A git-svn clone: git history mirrored from a Subversion repository, synced with git svn instead of pull and push.

import Foundation

public struct SVNStatus: Equatable, Sendable {
    /// Set when the repository has an `svn-remote` in its config.
    public var isSVN = false
    /// `svn-remote.svn.url`.
    public var url: String?
    /// The ref git svn fetches the main line into, e.g. `refs/remotes/origin/trunk`.
    var trackingRef: String?
    /// Whether a git with git-svn support was found.
    public var isAvailable = true
    /// Local commits not yet sent to Subversion.
    public var unsentCount = 0

    public static let missingMessage = "git svn isn't available: Apple's git leaves it out. Install it with "
        + "\u{201C}brew install git subversion\u{201D}, then try again."

    /// `svn-remote.<name>.url` and `.fetch` from `git config --get-regexp`; the first remote wins.
    init(configValues values: [String: String]) {
        let urlKey = values.keys.filter { $0.hasPrefix("svn-remote.") && $0.hasSuffix(".url") }.min()
        guard let urlKey else { return }
        isSVN = true
        url = values[urlKey]
        let remote = urlKey.dropLast(".url".count)
        // `trunk:refs/remotes/origin/trunk`, or `:refs/remotes/git-svn` for a clone without a layout.
        trackingRef = values["\(remote).fetch"]?.split(separator: ":", maxSplits: 1).last.map(String.init)
    }

    init() {}
}
