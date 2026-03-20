// Views/QuickActions/QuickActionResult.swift
// Grove

import Foundation

// MARK: - QuickActionResultKind

/// The category of a ``QuickActionResult``, used for icons and grouping.
enum QuickActionResultKind: Sendable {
    /// A named navigation destination (Working Copy, History, Stashes, etc.).
    case navigationItem
    /// A local Git branch.
    case branch
    /// A remote-tracking branch.
    case remoteBranch
    /// A Git tag.
    case tag
    /// A file path in the working tree or history.
    case filePath
    /// A commit identified by SHA.
    case commit

    // MARK: Display

    /// SF Symbol name for the result row icon.
    var systemImage: String {
        switch self {
        case .navigationItem: return "sidebar.left"
        case .branch:         return "arrow.triangle.branch"
        case .remoteBranch:   return "externaldrive"
        case .tag:            return "tag"
        case .filePath:       return "doc.text"
        case .commit:         return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }

    /// Short human-readable type label shown at the trailing edge of a result row.
    var typeLabel: String {
        switch self {
        case .navigationItem: return "View"
        case .branch:         return "Branch"
        case .remoteBranch:   return "Remote"
        case .tag:            return "Tag"
        case .filePath:       return "File"
        case .commit:         return "Commit"
        }
    }
}

// MARK: - QuickActionResult

/// A single item surfaced by the Quick Actions command palette.
struct QuickActionResult: Identifiable, Sendable {

    // MARK: Identity

    let id: String

    // MARK: Display

    /// Primary display text (branch name, file path, commit summary, etc.).
    let title: String

    /// Optional secondary text (e.g. commit SHA, remote URL).
    let subtitle: String?

    /// Category used for the icon and type label.
    let kind: QuickActionResultKind

    // MARK: Action

    /// The ``SidebarItem`` to select when this result is activated.
    ///
    /// `nil` for results that require custom handling (e.g. file-path navigation).
    let sidebarItem: SidebarItem?

    // MARK: Convenience Initialisers

    static func navigation(item: SidebarItem, title: String) -> QuickActionResult {
        QuickActionResult(
            id: "nav-\(title)",
            title: title,
            subtitle: nil,
            kind: .navigationItem,
            sidebarItem: item
        )
    }

    static func branch(_ branch: BranchInfo) -> QuickActionResult {
        QuickActionResult(
            id: "branch-\(branch.id)",
            title: branch.name,
            subtitle: branch.upstream,
            kind: branch.isLocal ? .branch : .remoteBranch,
            sidebarItem: branch.isLocal ? .branch(branch) : .remoteBranch(branch)
        )
    }

    static func tag(_ tag: TagInfo) -> QuickActionResult {
        QuickActionResult(
            id: "tag-\(tag.id)",
            title: tag.name,
            subtitle: String(tag.targetSHA.prefix(7)),
            kind: .tag,
            sidebarItem: .tag(tag)
        )
    }

    static func filePath(_ path: String) -> QuickActionResult {
        QuickActionResult(
            id: "file-\(path)",
            title: URL(fileURLWithPath: path).lastPathComponent,
            subtitle: path,
            kind: .filePath,
            sidebarItem: nil
        )
    }

    static func commit(_ commit: CommitInfo) -> QuickActionResult {
        QuickActionResult(
            id: "commit-\(commit.id)",
            title: commit.summary,
            subtitle: commit.shortSHA,
            kind: .commit,
            sidebarItem: nil
        )
    }
}
