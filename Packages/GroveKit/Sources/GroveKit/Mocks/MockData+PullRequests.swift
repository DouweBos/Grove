// Mocks/MockData+PullRequests.swift
// GroveKit
//
// Fake pull requests, comments and reflog entries.

import Foundation

extension MockData {

    // MARK: Pull Requests

    static let pullRequests: [PullRequestInfo] = {
        let now = Date()
        let cal = Calendar.current
        return [
            PullRequestInfo(
                id: 47,
                title: "feat: add pull request list and detail views",
                body: "Implements the Pull Requests feature using `gh` CLI.\n\nIncludes:\n- PR list with filter tabs\n- Detail panel with comments\n- Check Out / Close / Merge actions",
                authorName: authorJane.name,
                authorAvatarURL: nil,
                state: .open,
                sourceBranch: "feature/pull-requests",
                targetBranch: "main",
                createdDate: cal.date(byAdding: .hour, value: -6, to: now)!,
                updatedDate: cal.date(byAdding: .minute, value: -45, to: now)!,
                isDraft: false,
                labels: [
                    PRLabel(id: "enhancement", name: "enhancement", color: "0075ca"),
                    PRLabel(id: "ui", name: "ui", color: "e4e669")
                ],
                reviewers: [authorAlice.name],
                checksStatus: .passing
            ),
            PullRequestInfo(
                id: 46,
                title: "feat: blame view with per-line author annotations",
                body: "Adds a blame view that annotates each line of a file with its commit and author.",
                authorName: authorBob.name,
                authorAvatarURL: nil,
                state: .open,
                sourceBranch: "feature/blame-view",
                targetBranch: "main",
                createdDate: cal.date(byAdding: .day, value: -2, to: now)!,
                updatedDate: cal.date(byAdding: .hour, value: -3, to: now)!,
                isDraft: true,
                labels: [
                    PRLabel(id: "enhancement", name: "enhancement", color: "0075ca")
                ],
                reviewers: [],
                checksStatus: .pending
            ),
            PullRequestInfo(
                id: 45,
                title: "fix: stash diff crash when SHA is invalid",
                body: "Guards against stash entries whose stored SHA is no longer reachable in the object store.",
                authorName: authorAlice.name,
                authorAvatarURL: nil,
                state: .merged,
                sourceBranch: "bugfix/stash-sha-crash",
                targetBranch: "main",
                createdDate: cal.date(byAdding: .day, value: -5, to: now)!,
                updatedDate: cal.date(byAdding: .day, value: -3, to: now)!,
                isDraft: false,
                labels: [
                    PRLabel(id: "bug", name: "bug", color: "d73a4a")
                ],
                reviewers: [authorJane.name],
                checksStatus: .passing
            ),
            PullRequestInfo(
                id: 44,
                title: "chore: migrate to Swift 5.10 strict concurrency",
                body: nil,
                authorName: authorJane.name,
                authorAvatarURL: nil,
                state: .closed,
                sourceBranch: "chore/strict-concurrency",
                targetBranch: "main",
                createdDate: cal.date(byAdding: .day, value: -10, to: now)!,
                updatedDate: cal.date(byAdding: .day, value: -8, to: now)!,
                isDraft: false,
                labels: [
                    PRLabel(id: "chore", name: "chore", color: "e4e669")
                ],
                reviewers: [],
                checksStatus: .failing
            )
        ]
    }()

    // MARK: PR Comments

    public static let prComments: [PRComment] = {
        let now = Date()
        let cal = Calendar.current
        return [
            PRComment(
                id: "comment-0",
                authorName: authorAlice.name,
                authorAvatarURL: nil,
                body: "Looks great overall! Left a few minor nits inline.",
                createdDate: cal.date(byAdding: .hour, value: -4, to: now)!,
                isReview: true
            ),
            PRComment(
                id: "comment-1",
                authorName: authorBob.name,
                authorAvatarURL: nil,
                body: "Should we add a `#Preview` for `PRActionBar` in isolation too?",
                createdDate: cal.date(byAdding: .hour, value: -3, to: now)!,
                isReview: false
            ),
            PRComment(
                id: "comment-2",
                authorName: authorJane.name,
                authorAvatarURL: nil,
                body: "Good call — added a standalone preview in the latest commit.",
                createdDate: cal.date(byAdding: .hour, value: -2, to: now)!,
                isReview: false
            ),
            PRComment(
                id: "comment-3",
                authorName: authorAlice.name,
                authorAvatarURL: nil,
                body: "LGTM. Approved.",
                createdDate: cal.date(byAdding: .minute, value: -45, to: now)!,
                isReview: true
            )
        ]
    }()

    // MARK: Reflog

    static let reflogEntries: [ReflogEntry] = {
        var entries: [ReflogEntry] = []
        let messages = [
            "commit: feat: add OAuth2 authentication flow",
            "commit: refactor: split AuthManager into focused services",
            "pull: Fast-forward",
            "checkout: moving from develop to main",
            "merge feature/auth: Merge made by the 'ort' strategy.",
            "commit (amend): fix: prevent token refresh race condition",
            "rebase (finish): returning to refs/heads/main",
            "push origin main"
        ]
        let now = Date()
        for (i, msg) in messages.enumerated() {
            let commit = commits[min(i, commits.count - 1)]
            let prev   = commits[min(i + 1, commits.count - 1)]
            entries.append(ReflogEntry(
                id: "reflog-\(i)",
                oldSHA: prev.id,
                newSHA: commit.id,
                committerName: authorJane.name,
                committerEmail: authorJane.email,
                date: Calendar.current.date(byAdding: .hour, value: -i, to: now)!,
                message: msg
            ))
        }
        return entries
    }()

    // MARK: PR Review Comments

    static let prReviewComments: [PRReviewComment] = {
        let now = Date()
        let hunk = "@@ -10,6 +10,8 @@ struct PRActionBar: View {\n     var body: some View {\n"
            + "-        HStack {\n+        HStack(spacing: 8) {\n+            Spacer()"
        return [
            PRReviewComment(id: 1, replyTo: nil, authorName: authorAlice.name, body: "Use `Theme.Spacing.sm` here.",
                            path: "Views/PRActionBar.swift", line: 13, diffHunk: hunk, createdDate: now.addingTimeInterval(-9000)),
            PRReviewComment(id: 2, replyTo: 1, authorName: authorJane.name, body: "Done.",
                            path: "Views/PRActionBar.swift", line: 13, diffHunk: hunk, createdDate: now.addingTimeInterval(-7000))
        ]
    }()
}
