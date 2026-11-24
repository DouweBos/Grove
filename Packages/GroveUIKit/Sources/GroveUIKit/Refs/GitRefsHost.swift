// Refs/GitRefsHost.swift
// GroveUIKit
//
// What only the app around the refs sidebar can do.

#if os(macOS)
import GroveKit
import SwiftUI

/// The app's part of the refs sidebar. Every closure is optional; nil leaves its item out.
/// Changes to git go through the model's `actions.commands`; these are what git alone can't do.
public struct GitRefsHost {
    /// Pinned, archived and protected branches and the base, kept by the app.
    public var marks = GitBranchMarks()
    public var setPinned: ((_ branch: String, _ pinned: Bool) -> Void)?
    public var setArchived: ((_ branch: String, _ archived: Bool) -> Void)?
    /// Local branches the app lists itself in `GitRefsSidebar`'s `branches` slot, e.g. a stack's layers.
    public var hiddenBranches: Set<String> = []
    /// False when the app's commands already show their failures, e.g. in a banner of its own.
    public var showsFailures = true
    /// Opens another worktree, e.g. in a new tab; also on double-click.
    public var openWorktree: ((WorktreeInfo) -> Void)?
    /// Runs this window's git in another worktree.
    public var switchWorktree: ((WorktreeInfo) -> Void)?
    public var removeWorktree: ((WorktreeInfo) -> Void)?
    public var pruneWorktrees: (() -> Void)?
    /// Opens a cloned submodule, e.g. in a new tab; also on double-click.
    public var openSubmodule: ((SubmoduleInfo) -> Void)?
    public var openSubmoduleHere: ((SubmoduleInfo) -> Void)?
    public var addSubmodule: (() -> Void)?
    /// Starts a pull request for a branch by its name on the remote.
    public var createPullRequest: ((String) -> Void)?
    /// Shows CI runs for a branch by its name on the remote.
    public var showRuns: ((String) -> Void)?
    /// Selects a ref's commit in History.
    public var revealInHistory: ((_ sha: String, _ item: GitRefItem) -> Void)?
    /// Saves a ref's files, e.g. as a ZIP.
    public var exportFiles: ((String) -> Void)?
    /// Compares a ref with the checked-out branch.
    public var compare: ((_ base: String, _ compare: String) -> Void)?
    /// The app's items leading a local branch's menu, e.g. finishing a flow branch.
    public var branchMenu: ((BranchInfo) -> AnyView)?
    /// A drop of `payload` on `target` the app handles itself, e.g. moving a stack; nil leaves it to the kit.
    public var drop: ((_ payload: String, _ target: BranchInfo, _ option: Bool) -> GitRefCustomDrop?)?

    public init() {}
}
#endif
