// Models/SwiftDataModels.swift
// Grove
//
// SwiftData persistent models for Grove.
// These are implementation details of RepositoryManager and must NOT
// be exposed through RepositoryManagerProtocol.  Views and ViewModels
// always work with the lightweight Codable types defined in
// RepositoryManagerProtocol.swift.

import SwiftData
import Foundation

// MARK: - RepositoryBookmark

/// Persistent record for a bookmarked repository.
///
/// The `path` column carries a `.unique` constraint so the store rejects
/// duplicate paths at the database level, mirroring the runtime guard in
/// ``RepositoryManager/addBookmark(path:displayName:groupID:)``.
@Model
final class RepositoryBookmark {

    // MARK: Attributes

    /// Absolute filesystem path to the repository's working directory.
    @Attribute(.unique)
    var path: String

    /// Human-readable label shown in the sidebar.
    var displayName: String

    /// When the bookmark was first created.
    var addedDate: Date

    /// The most recent time the repository window was opened, if any.
    var lastOpenedDate: Date?

    /// Position within its containing group (or the ungrouped list).
    var sortOrder: Int

    // MARK: Relationships

    /// The group this bookmark belongs to, or `nil` for ungrouped bookmarks.
    var group: RepositoryGroup?

    // MARK: Init

    init(
        path: String,
        displayName: String,
        addedDate: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.path = path
        self.displayName = displayName
        self.addedDate = addedDate
        self.sortOrder = sortOrder
    }
}

// MARK: - RepositoryGroup

/// Persistent record for a sidebar group that contains repository bookmarks.
///
/// The `groupID` field is the stable identifier exchanged with the protocol
/// layer; it is kept separate from SwiftData's implicit `PersistentIdentifier`
/// so the `BookmarkGroupData.id: UUID` contract is preserved without change.
@Model
final class RepositoryGroup {

    // MARK: Attributes

    /// Stable identifier exchanged with the protocol layer (`BookmarkGroupData.id`).
    @Attribute(.unique)
    var groupID: UUID

    /// Display name shown in the sidebar section header.
    var name: String

    /// Position in the sidebar group list.
    var sortOrder: Int

    /// Whether the group is expanded in the sidebar.
    var isExpanded: Bool

    // MARK: Relationships

    /// All bookmarks that belong to this group.
    ///
    /// `deleteRule: .nullify` keeps bookmarks alive when the group is deleted
    /// — ``RepositoryManager/deleteGroup(id:)`` manually ungroups them.
    @Relationship(deleteRule: .nullify, inverse: \RepositoryBookmark.group)
    var repositories: [RepositoryBookmark]

    // MARK: Init

    init(
        name: String,
        sortOrder: Int = 0,
        isExpanded: Bool = true
    ) {
        self.groupID = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isExpanded = isExpanded
        self.repositories = []
    }
}

// MARK: - UserProfile

/// Persistent record for a git author/committer identity profile.
///
/// Multiple profiles are supported (e.g. work vs. personal).  Exactly one
/// profile should have `isDefault == true` at any time.
@Model
final class UserProfile {

    // MARK: Attributes

    /// Stable identifier for this profile.
    @Attribute(.unique)
    var profileID: UUID

    /// Committer name as it will appear in git commits.
    var name: String

    /// Committer email as it will appear in git commits.
    var email: String

    /// GPG or SSH signing key fingerprint, if commit signing is enabled.
    var signingKeyID: String?

    /// Whether this profile is the active default.
    var isDefault: Bool

    // MARK: Init

    init(name: String, email: String) {
        self.profileID = UUID()
        self.name = name
        self.email = email
        self.isDefault = false
    }
}

// MARK: - CommitTemplate

/// Persistent record for a reusable commit message template.
///
/// Managed in the Commit Templates preferences tab.
@Model
final class CommitTemplate {

    // MARK: Attributes

    @Attribute(.unique)
    var templateID: UUID

    /// Display name for the template.
    var name: String

    /// Full commit message content.
    var content: String

    /// Position in the template list.
    var sortOrder: Int

    /// Whether this is the default template proposed in the commit composer.
    var isDefault: Bool

    // MARK: Init

    init(name: String, content: String, sortOrder: Int = 0) {
        self.templateID = UUID()
        self.name = name
        self.content = content
        self.sortOrder = sortOrder
        self.isDefault = false
    }
}

// MARK: - GitServiceAccount

/// Persistent record for a connected Git hosting service account.
///
/// Tokens are stored in the macOS Keychain — only a reference key is
/// persisted here, never the raw credential.
@Model
final class GitServiceAccount {

    // MARK: Attributes

    @Attribute(.unique)
    var accountID: UUID

    /// The hosting provider (github, gitlab, bitbucket, azureDevOps).
    var provider: String

    /// Human-readable label (e.g. "Work GitHub", "Personal GitLab").
    var displayName: String

    /// The username or handle on the service.
    var username: String

    /// Reference key into the macOS Keychain where the token is stored.
    /// Never contains the actual secret.
    var tokenKeychainRef: String

    // MARK: Init

    init(provider: String, displayName: String, username: String, tokenKeychainRef: String) {
        self.accountID = UUID()
        self.provider = provider
        self.displayName = displayName
        self.username = username
        self.tokenKeychainRef = tokenKeychainRef
    }
}

// MARK: - AppPreferences

/// Persistent singleton for application-level preferences.
///
/// Only one `AppPreferences` record should exist in the store at any time.
/// ``RepositoryManager`` (or a dedicated PreferencesManager) is responsible
/// for ensuring the singleton is created on first launch.
@Model
final class AppPreferences {

    // MARK: Attributes

    /// Default directory proposed in the clone and init dialogs.
    var defaultCloneDirectory: String

    /// How often (in minutes) Grove automatically fetches all remotes.
    /// Zero means auto-fetch is disabled.
    var autoFetchIntervalMinutes: Int

    /// When `true`, the toolbar renders in the compact single-row layout.
    var compactToolbar: Bool

    /// Maximum number of commits shown in the history list.
    var commitHistoryLimit: Int

    /// When `true`, Grove shows a confirmation alert before discarding a hunk.
    var warnOnChunkDiscard: Bool

    /// When `true`, the Quick Start screen is shown on every launch.
    var showQuickStartOnLaunch: Bool

    /// The terminal application to open when "Open in Terminal" is invoked.
    var terminalApp: String

    // MARK: Init

    init() {
        self.defaultCloneDirectory = "~/Projects"
        self.autoFetchIntervalMinutes = 0
        self.compactToolbar = false
        self.commitHistoryLimit = 500
        self.warnOnChunkDiscard = true
        self.showQuickStartOnLaunch = true
        self.terminalApp = "Terminal"
    }
}
