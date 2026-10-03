// Models/PRTypes.swift
// GroveKit
//
// Pull request domain types.

import Foundation

// MARK: - PullRequestInfo

/// A single pull request returned by the GitHub CLI.
public struct PullRequestInfo: Identifiable, Hashable, Sendable {
    /// PR number used as the stable identifier.
    public let id: Int
    public let title: String
    /// Markdown description body, if any.
    public let body: String?
    public let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    public let state: PRState
    public let sourceBranch: String
    public let targetBranch: String
    public let createdDate: Date
    public let updatedDate: Date
    public let isDraft: Bool
    public let labels: [PRLabel]
    public let reviewers: [String]
    public let checksStatus: PRChecksStatus
    /// The head commit, where the service reports one.
    var headSHA: String?

    public init(id: Int, title: String, body: String? = nil, authorName: String, authorAvatarURL: String? = nil, state: PRState, sourceBranch: String, targetBranch: String, createdDate: Date, updatedDate: Date, isDraft: Bool, labels: [PRLabel], reviewers: [String], checksStatus: PRChecksStatus, headSHA: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.state = state
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.isDraft = isDraft
        self.labels = labels
        self.reviewers = reviewers
        self.checksStatus = checksStatus
        self.headSHA = headSHA
    }
}

// MARK: - PRState

/// Open / closed / merged state of a pull request.
public enum PRState: String, Hashable, Sendable {
    case open
    case closed
    case merged
}

// MARK: - PRLabel

/// A label attached to a pull request.
public struct PRLabel: Identifiable, Hashable, Sendable {
    /// Label name used as the stable identifier.
    public let id: String
    public let name: String
    /// Hex colour string, e.g. `"0075ca"`.
    public let color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

// MARK: - PRChecksStatus

/// Aggregate status of all CI checks on a pull request.
public enum PRChecksStatus: Hashable, Sendable {
    case pending
    case passing
    case failing
    case none
}

// MARK: - PRComment

/// A single comment or review on a pull request.
public struct PRComment: Identifiable, Hashable, Sendable {
    public let id: String
    public let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    /// Markdown body text of the comment.
    public let body: String
    public let createdDate: Date
    /// True when the comment is a formal review (approve / request-changes).
    public let isReview: Bool

    public init(id: String, authorName: String, authorAvatarURL: String? = nil, body: String, createdDate: Date, isReview: Bool) {
        self.id = id
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.body = body
        self.createdDate = createdDate
        self.isReview = isReview
    }
}
