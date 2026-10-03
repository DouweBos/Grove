// Mocks/MockData.swift
// GroveKit
//
// Fake authors, commits and refs for previews and tests.

import Foundation

// MARK: - MockData

/// Static fake data used by ``MockGitRepository``.
///
/// All values are crafted to look realistic so that views developed against
/// the mock closely resemble what the real engine will produce.
public enum MockData {

    // MARK: Authors

    static let authorJane = (name: "Jane Developer", email: "jane@example.com")
    static let authorBob  = (name: "Bob Contributor", email: "bob@example.com")
    static let authorAlice = (name: "Alice Reviewer", email: "alice@example.com")

    // MARK: Commits

    public static let commits: [CommitInfo] = {
        let calendar = Calendar.current
        var result: [CommitInfo] = []

        // swiftlint:disable:next large_tuple
        let data: [(String, String, String?, String, [String], Bool)] = [
            // (sha, summary, body?, authorEmail, parentSHAs, isSigned)
            (
                "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                "feat: add OAuth2 authentication flow",
                "Implements RFC 6749 authorisation code grant.\n\nIncludes PKCE extension and automatic token refresh.",
                authorJane.email,
                ["b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"],
                true
            ),
            (
                "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
                "refactor: split AuthManager into focused services",
                nil,
                authorJane.email,
                ["c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"],
                false
            ),
            (
                "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
                "fix: prevent token refresh race condition",
                "Multiple concurrent requests were each triggering a refresh.\nNow uses a single shared Task to serialise the refresh.",
                authorBob.email,
                ["d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"],
                false
            ),
            (
                "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
                "feat: repository browser with drag-and-drop reorder",
                nil,
                authorAlice.email,
                ["e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"],
                true
            ),
            (
                "e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6",
                "Merge pull request #42 from feature/dark-mode",
                "Merges the dark mode branch into main.\n\nReviewed by Alice.",
                authorAlice.email,
                ["f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                 "06a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "feat: dark mode support for all primary views",
                nil,
                authorBob.email,
                ["16a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "16a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "chore: update SwiftLint to 0.55.1",
                nil,
                authorJane.email,
                ["26a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "26a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "test: add unit tests for CommitGraph lane algorithm",
                "Covers merge commits, cross-lane edges, and single-branch linear history.",
                authorAlice.email,
                ["36a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "36a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "perf: lazy-load commit graph rows with AsyncSequence",
                nil,
                authorJane.email,
                ["46a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "46a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "feat: hunk-level and line-level staging in diff view",
                "Implements partial patch construction using git_apply.\n\nSupports stage/unstage at hunk and individual line granularity.",
                authorBob.email,
                ["56a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                true
            ),
            (
                "56a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "fix: crash when staging empty file",
                nil,
                authorJane.email,
                ["66a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "66a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "docs: document GitRepositoryProtocol contract",
                nil,
                authorAlice.email,
                ["76a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "76a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "build: add Clibgit2 SPM package reference",
                nil,
                authorJane.email,
                ["86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "chore: initial project scaffold",
                "Bootstrap commit from WS0.\n\nEstablishes directory structure, protocols, and mocks.",
                authorJane.email,
                [],
                false
            )
        ]

        let now = Date()
        for (index, item) in data.enumerated() {
            let (sha, summary, body, email, parents, signed) = item
            let authorName = email == authorJane.email ? authorJane.name
                           : email == authorBob.email  ? authorBob.name
                           : authorAlice.name
            let date = calendar.date(byAdding: .hour, value: -(index * 4), to: now)!
            let message = body != nil ? "\(summary)\n\n\(body!)" : summary
            result.append(CommitInfo(
                id: sha,
                message: message,
                summary: summary,
                body: body,
                authorName: authorName,
                authorEmail: email,
                authorDate: date,
                committerName: authorName,
                committerEmail: email,
                committerDate: date,
                parentIDs: parents,
                isSigned: signed
            ))
        }
        return result
    }()

    // MARK: Branches

    public static let branches: [BranchInfo] = [
        BranchInfo(
            id: "refs/heads/main",
            name: "main",
            isLocal: true,
            isRemote: false,
            isHEAD: true,
            targetSHA: commits[0].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/main",
            ahead: 2,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/develop",
            name: "develop",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[3].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/develop",
            ahead: 0,
            behind: 1
        ),
        BranchInfo(
            id: "refs/heads/feature/auth",
            name: "feature/auth",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[2].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/feature/auth",
            ahead: 3,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/feature/ui-overhaul",
            name: "feature/ui-overhaul",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[5].id,
            remoteName: nil,
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/bugfix/crash-on-empty-stash",
            name: "bugfix/crash-on-empty-stash",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[10].id,
            remoteName: nil,
            upstream: nil,
            ahead: 1,
            behind: 0
        ),
        // Remote branches
        BranchInfo(
            id: "refs/remotes/origin/main",
            name: "origin/main",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[2].id,
            remoteName: "origin",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/remotes/origin/develop",
            name: "origin/develop",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[4].id,
            remoteName: "origin",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/remotes/upstream/main",
            name: "upstream/main",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[6].id,
            remoteName: "upstream",
            upstream: nil,
            ahead: 0,
            behind: 0
        )
    ]

    // MARK: Remotes

    public static let remotes: [RemoteInfo] = [
        RemoteInfo(
            id: "origin",
            name: "origin",
            url: "git@github.com:example/my-app.git",
            pushURL: nil
        ),
        RemoteInfo(
            id: "upstream",
            name: "upstream",
            url: "https://github.com/upstream-org/my-app.git",
            pushURL: "git@github.com:upstream-org/my-app.git"
        )
    ]

    // MARK: Tags

    public static let tags: [TagInfo] = [
        TagInfo(
            id: "v1.0.0",
            name: "v1.0.0",
            targetSHA: commits[13].id,
            isAnnotated: true,
            message: "First stable release.\n\nIncludes all Phase A bootstrap work.",
            taggerName: authorJane.name,
            taggerDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        ),
        TagInfo(
            id: "v1.1.0",
            name: "v1.1.0",
            targetSHA: commits[9].id,
            isAnnotated: true,
            message: "Adds hunk/line-level staging.",
            taggerName: authorBob.name,
            taggerDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
        ),
        TagInfo(
            id: "v1.1.1",
            name: "v1.1.1",
            targetSHA: commits[10].id,
            isAnnotated: false,
            message: nil,
            taggerName: nil,
            taggerDate: nil
        )
    ]
}
