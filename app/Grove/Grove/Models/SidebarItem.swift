// Models/SidebarItem.swift
// Grove
//
// The navigation item contract shared between the Sidebar (WS4)
// and the content router (WS2).  Kept intentionally flat — the
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
