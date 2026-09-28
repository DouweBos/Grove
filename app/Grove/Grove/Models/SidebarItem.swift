// Models/SidebarItem.swift
// Grove
//
// The navigation item contract shared between the Sidebar
// and the content router.  Kept intentionally flat — the
// router switches on this enum and hands the associated value down
// to the correct view.

import Foundation

/// Represents every selectable destination inside a repository window's sidebar.
enum SidebarItem: Hashable, Sendable {
    /// The Working Copy view — shows staged/unstaged files and the commit composer.
    case workingCopy
    /// The commit History view — shows the full commit log with graph.
    case history
    /// The Stashes list view.
    case stashes
    /// The Reflog browser view — shows all HEAD movements via `git reflog`.
    case reflog
    /// The Blame view — annotates a file with per-line commit information.
    case blame
    /// The Pull Requests list view.
    case pullRequests
    /// The Branches Review view — shows stale and merged branches.
    case branchesReview
    /// The in-repository Settings / Preferences view.
    case settings
    /// History filtered to a specific local branch.
    case branch(BranchInfo)
    /// History filtered to a specific remote-tracking branch.
    case remoteBranch(BranchInfo)
    /// History filtered to a specific tag.
    case tag(TagInfo)
}

// MARK: - RepositoryTab

/// Top-level destinations shown as pills in the window toolbar.
enum RepositoryTab: CaseIterable, Hashable {
    case changes, history, stashes, pullRequests, reflog, review, blame, settings

    /// Always shown; the rest live in the toolbar's More menu and get a pill only while open.
    static let primary: [RepositoryTab] = [.changes, .history, .stashes, .pullRequests]
    static let secondary: [RepositoryTab] = [.reflog, .review, .blame, .settings]

    var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .stashes: "Stashes"
        case .pullRequests: "Pull Requests"
        case .reflog: "Reflog"
        case .review: "Branches Review"
        case .blame: "Blame"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .changes: "tray"
        case .history: "clock"
        case .stashes: "tray.2"
        case .pullRequests: "arrow.triangle.pull"
        case .reflog: "clock.arrow.circlepath"
        case .review: "checklist"
        case .blame: "text.line.first.and.arrowtriangle.forward"
        case .settings: "gearshape"
        }
    }

    var item: SidebarItem {
        switch self {
        case .changes: .workingCopy
        case .history: .history
        case .stashes: .stashes
        case .pullRequests: .pullRequests
        case .reflog: .reflog
        case .review: .branchesReview
        case .blame: .blame
        case .settings: .settings
        }
    }

    /// Branch, remote and tag selections are filtered history, so they keep History lit.
    init(item: SidebarItem) {
        switch item {
        case .workingCopy: self = .changes
        case .history, .branch, .remoteBranch, .tag: self = .history
        case .stashes: self = .stashes
        case .pullRequests: self = .pullRequests
        case .reflog: self = .reflog
        case .branchesReview: self = .review
        case .blame: self = .blame
        case .settings: self = .settings
        }
    }
}
