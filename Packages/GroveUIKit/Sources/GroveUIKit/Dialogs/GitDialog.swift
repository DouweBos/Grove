// Dialogs/GitDialog.swift
// GroveUIKit
//
// Which dialog to show, and what it runs against.

#if os(macOS)
import GroveKit
import SwiftUI

public enum GitDialog: Identifiable, Hashable, Sendable {
    case fetch
    case pull
    /// A nil branch pushes the checked-out one.
    case push(branch: String? = nil)
    case sync
    /// Starts at `from`, else at the checked-out branch.
    case createBranch(from: String? = nil)
    case renameBranch(String)
    /// The checked-out branch, through `GitCommand.renameCurrentBranch`.
    case renameCurrentBranch
    case deleteBranch(BranchInfo)
    case trackRemoteBranch(BranchInfo)
    case merge
    case rebase
    /// Opens with only `paths` ticked; nil stashes everything.
    case stash(paths: [String]? = nil)
    case snapshot
    /// Tags `at`, else HEAD.
    case createTag(at: String? = nil)
    case addRemote
    case editRemote(RemoteInfo)
    case branchFromStash(index: Int)

    public var id: String {
        switch self {
        case .push(let branch): "push:\(branch ?? "")"
        case .createBranch(let start): "createBranch:\(start ?? "")"
        case .renameBranch(let name): "renameBranch:\(name)"
        case .deleteBranch(let branch): "deleteBranch:\(branch.id)"
        case .trackRemoteBranch(let branch): "track:\(branch.id)"
        case .stash(let paths): "stash:\(paths?.joined(separator: "\n") ?? "")"
        case .createTag(let target): "createTag:\(target ?? "")"
        case .editRemote(let remote): "editRemote:\(remote.id)"
        case .branchFromStash(let index): "branchFromStash:\(index)"
        default: kind
        }
    }

    /// The dialog without its subject, e.g. for an app's telemetry.
    public var kind: String {
        switch self {
        case .fetch: "fetch"
        case .pull: "pull"
        case .push: "push"
        case .sync: "sync"
        case .createBranch: "create_branch"
        case .renameBranch, .renameCurrentBranch: "rename_branch"
        case .deleteBranch: "delete_branch"
        case .trackRemoteBranch: "track"
        case .merge: "merge"
        case .rebase: "rebase"
        case .stash: "stash"
        case .snapshot: "snapshot"
        case .createTag: "create_tag"
        case .addRemote: "add_remote"
        case .editRemote: "edit_remote"
        case .branchFromStash: "branch_from_stash"
        }
    }
}

/// What a dialog reads, runs its commands through, and tells the app.
public struct GitDialogContext {
    /// Read only: every change goes through `commands`.
    public var repository: any GitRepositoryProtocol
    /// Last-read branches and remotes, so a dialog opens without waiting on git.
    public var refs: RepositoryRefs
    /// Runs the dialog's changes; its `features` decide what the dialog offers.
    public var commands: any GitCommandPerforming
    /// Leads every branch picker, e.g. the branch a session started from.
    public var preferredBranch: String?
    /// Takes a new branch that isn't checked out, so it can be undone.
    public var undo: GitUndoManager?
    /// After a dialog changed the repository, whether or not it then failed; nil when `commands` refresh on their own.
    public var onChange: (() async -> Void)?
    /// Offers Pin Branch in New Branch.
    public var pinBranch: ((String) async -> Void)?
    /// After Add Remote, e.g. to fetch it.
    public var onRemoteAdded: ((String) -> Void)?
    /// Lets Delete Branch remove the worktree that has the branch checked out.
    public var worktrees: GitDialogWorktrees?

    public init(repository: any GitRepositoryProtocol, refs: RepositoryRefs, commands: any GitCommandPerforming) {
        self.repository = repository
        self.refs = refs
        self.commands = commands
    }

    var features: GitFeatures { commands.features }

    var headBranch: BranchInfo? {
        refs.localBranches.first(where: \.isHEAD) ?? repository.currentBranch
    }

    /// Local branches other than HEAD's, the preferred one first.
    var otherLocalBranches: [String] {
        var names = refs.localBranches.filter { !$0.isHEAD }.map(\.name)
        if let preferredBranch, let index = names.firstIndex(of: preferredBranch) {
            names.insert(names.remove(at: index), at: 0)
        }
        return names
    }

    func changed() async {
        await onChange?()
    }
}

/// How Delete Branch reaches worktrees, which aren't commands.
public struct GitDialogWorktrees {
    /// Another worktree that has the branch checked out.
    public var checkingOut: (BranchInfo) -> WorktreeInfo?
    /// Removes the worktree, `force` with its changes, then deletes the branch, `forceBranch` even if unmerged.
    public var remove: (_ worktree: WorktreeInfo, _ force: Bool, _ branch: BranchInfo, _ forceBranch: Bool) async throws -> Void
    public var open: (WorktreeInfo) -> Void

    public init(checkingOut: @escaping (BranchInfo) -> WorktreeInfo?,
                remove: @escaping (WorktreeInfo, Bool, BranchInfo, Bool) async throws -> Void,
                open: @escaping (WorktreeInfo) -> Void) {
        self.checkingOut = checkingOut
        self.remove = remove
        self.open = open
    }
}
#endif
