// Models/PRTypes.swift
// GroveKit
//
// Pull request domain types.

import Foundation

// MARK: - PullRequestInfo

/// A single pull request returned by the GitHub CLI.
struct PullRequestInfo: Identifiable, Hashable, Sendable {
    /// PR number used as the stable identifier.
    let id: Int
    let title: String
    /// Markdown description body, if any.
    let body: String?
    let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    let state: PRState
    let sourceBranch: String
    let targetBranch: String
    let createdDate: Date
    let updatedDate: Date
    let isDraft: Bool
    let labels: [PRLabel]
    let reviewers: [String]
    let checksStatus: PRChecksStatus
    /// The head commit, where the service reports one.
    var headSHA: String?
}

// MARK: - PRState

/// Open / closed / merged state of a pull request.
enum PRState: String, Hashable, Sendable {
    case open
    case closed
    case merged
}

// MARK: - PRLabel

/// A label attached to a pull request.
struct PRLabel: Identifiable, Hashable, Sendable {
    /// Label name used as the stable identifier.
    let id: String
    let name: String
    /// Hex colour string, e.g. `"0075ca"`.
    let color: String
}

// MARK: - PRChecksStatus

/// Aggregate status of all CI checks on a pull request.
enum PRChecksStatus: Hashable, Sendable {
    case pending
    case passing
    case failing
    case none
}

// MARK: - PRComment

/// A single comment or review on a pull request.
struct PRComment: Identifiable, Hashable, Sendable {
    let id: String
    let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    /// Markdown body text of the comment.
    let body: String
    let createdDate: Date
    /// True when the comment is a formal review (approve / request-changes).
    let isReview: Bool
}
