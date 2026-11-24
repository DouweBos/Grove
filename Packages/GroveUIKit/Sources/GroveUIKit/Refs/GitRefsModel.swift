// Refs/GitRefsModel.swift
// GroveUIKit
//
// What the refs sidebar shows and asks: folders, the filter, open sections, drops and confirmations.

#if os(macOS)
import GroveKit
import Observation
import SwiftUI

/// A row the refs sidebar can select; `host` is one of the app's own rows, e.g. a stack.
public nonisolated enum GitRefItem: Hashable, Sendable {
    case branch(String)
    case remoteBranch(String)
    case tag(String)
    case worktree(String)
    case submodule(String)
    case host(String)
}

/// What the app, not git, knows about branches.
public nonisolated struct GitBranchMarks: Equatable, Sendable {
    /// Listed first in Branches, with a pin.
    public var pinned: Set<String>
    /// Hidden from Branches and listed under Archived, also when the branch is gone.
    public var archived: Set<String>
    /// Listed first with a lock, e.g. branches the app won't let anyone delete.
    public var protected: Set<String>
    /// Leads the flat branches in place of the trunk, e.g. the branch a session started from.
    public var base: String?

    public init(pinned: Set<String> = [], archived: Set<String> = [], protected: Set<String> = [], base: String? = nil) {
        self.pinned = pinned
        self.archived = archived
        self.protected = protected
        self.base = base
    }
}

/// A sidebar folder opens for the checked-out branch and closes again once it leaves; one the person toggled stays.
public nonisolated struct GitFolderExpansion: Equatable, Sendable {
    public private(set) var isExpanded: Bool
    private var openedForHEAD: Bool

    public init(containsHEAD: Bool) {
        isExpanded = containsHEAD
        openedForHEAD = containsHEAD
    }

    public mutating func headChanged(contains: Bool) {
        if contains, !isExpanded {
            isExpanded = true
            openedForHEAD = true
        } else if !contains, openedForHEAD {
            isExpanded = false
            openedForHEAD = false
        }
    }

    public mutating func toggle(to expanded: Bool) {
        isExpanded = expanded
        openedForHEAD = false
    }
}

@MainActor
@Observable
public final class GitRefsModel {
    /// Runs every change through its `commands`; the app sets them, its undo and its refresh.
    public let actions: RefActionsViewModel
    public var refs: RepositoryRefs { actions.refs }

    /// Narrows every section to refs whose name contains it.
    public var filter = ""
    /// The Tags section, closed until asked for: thousands of tags make the first layout slow.
    public var tagsExpanded = false
    /// How many rows a long flat list shows before Show More.
    public internal(set) var rowLimits: [String: Int] = [:]
    static let pageSize = 300

    var folders: [String: GitFolderExpansion] = [:]
    var sections: [String: Bool] = [:]

    /// A drop waiting for confirmation.
    public internal(set) var pendingDrop: GitRefDrop?
    var dropError: String?
    var isRunningDrop = false
    var confirmation: RefConfirmation?
    /// A checkout that uncommitted changes blocked, offering to stash or discard them.
    var blockedCheckout: String?
    /// An error the sidebar shows when its commands don't show their own.
    var actionError: String?

    public init(actions: RefActionsViewModel) {
        self.actions = actions
    }

    var headName: String? { refs.localBranches.first(where: \.isHEAD)?.name }

    /// Errors from its actions or the last refs read, for an app whose commands show none.
    var errorMessage: String? { actionError ?? actions.errorMessage ?? refs.errorMessage }

    func dismissError() {
        actionError = nil
        actions.dismissError()
        refs.dismissError()
    }

    // MARK: Expansion

    func isExpanded(folder key: String, containsHEAD: Bool) -> Bool {
        folders[key]?.isExpanded ?? containsHEAD
    }

    public func setExpanded(folder key: String, _ expanded: Bool) {
        var expansion = folders[key] ?? GitFolderExpansion(containsHEAD: false)
        expansion.toggle(to: expanded)
        folders[key] = expansion
    }

    func headChanged(folder key: String, contains: Bool) {
        var expansion = folders[key] ?? GitFolderExpansion(containsHEAD: !contains)
        expansion.headChanged(contains: contains)
        folders[key] = expansion
    }

    func isSectionExpanded(_ key: String, default value: Bool) -> Bool { sections[key] ?? value }

    public func setSection(_ key: String, expanded: Bool) {
        if key == RefSection.tags { tagsExpanded = expanded } else { sections[key] = expanded }
    }

    func limit(_ key: String) -> Int { rowLimits[key] ?? Self.pageSize }

    func showMore(_ key: String) { rowLimits[key] = limit(key) + Self.pageSize * 4 }

    // MARK: Checkout

    /// Checks out `name`; when uncommitted changes block it, asks whether to stash or discard them.
    func checkout(_ name: String) async {
        if await actions.checkout(named: name) { return }
        guard (try? await actions.repository.status().contains(where: \.blocksCheckout)) == true else { return }
        actions.dismissError()
        blockedCheckout = name
    }

    func checkout(_ name: String, carrying carry: RefActionsViewModel.CheckoutCarry) async {
        blockedCheckout = nil
        await actions.checkout(named: name, carrying: carry)
    }

    /// Double-click: the worktree that has the branch, else a checkout here; a remote branch's local one if any.
    func activate(_ item: GitRefItem, features: GitFeatures, host: GitRefsHost) async {
        switch item {
        case .branch(let name):
            guard let branch = refs.localBranches.first(where: { $0.name == name }) else { return }
            if let worktree = actions.worktree(checkingOut: branch), let open = host.openWorktree {
                open(worktree)
            } else if !branch.isHEAD, features.contains(.checkout) {
                await checkout(name)
            }
        case .remoteBranch(let name):
            guard let branch = refs.remoteBranches.first(where: { $0.name == name }) else { return }
            let short = RefActionsViewModel.shortName(of: branch)
            if refs.localBranches.contains(where: { $0.name == short }) {
                await activate(.branch(short), features: features, host: host)
            } else if features.contains(.checkout) {
                await checkout(short)
            }
        case .worktree(let path):
            if let worktree = refs.worktrees.first(where: { $0.path == path }), !worktree.isPrunable { host.openWorktree?(worktree) }
        case .submodule(let path):
            if let submodule = refs.submodules.first(where: { $0.path == path }), submodule.state != .uninitialized {
                host.openSubmodule?(submodule)
            }
        case .tag, .host:
            break
        }
    }

    // MARK: Confirmations

    func confirm(_ confirmation: RefConfirmation) async {
        self.confirmation = nil
        switch confirmation {
        case .removeRemote(let remote): await actions.removeRemote(remote)
        case .deleteRemoteBranch(let branch): await actions.deleteRemoteBranch(branch)
        case .deleteTag(let tag): await actions.deleteTag(tag)
        case .removeSubmodule(let submodule): await actions.removeSubmodule(submodule)
        }
    }

    /// Runs a command the menus have no view model call for, e.g. pushing a tag.
    func run(_ command: GitCommand) async {
        do {
            try await actions.commands.perform(command)
        } catch {
            actionError = error.localizedDescription
        }
        await actions.didChangeRepository()
    }
}

enum RefConfirmation: Identifiable {
    case removeRemote(RemoteInfo)
    case deleteRemoteBranch(BranchInfo)
    case deleteTag(TagInfo)
    case removeSubmodule(SubmoduleInfo)

    var id: String {
        switch self {
        case .removeRemote(let remote): "remote:\(remote.id)"
        case .deleteRemoteBranch(let branch): "remoteBranch:\(branch.id)"
        case .deleteTag(let tag): "tag:\(tag.id)"
        case .removeSubmodule(let submodule): "submodule:\(submodule.id)"
        }
    }
}

enum RefSection {
    static let remotes = "remotes"
    static let tags = "tags"
    static let worktrees = "worktrees"
    static let archived = "archived"
    static let submodules = "submodules"
}

extension StatusEntry {
    /// Changes to tracked files; git checks out over untracked ones unless they'd be overwritten.
    var blocksCheckout: Bool {
        workdirStatus != .untracked && (indexStatus != .unmodified || workdirStatus != .unmodified)
    }
}
#endif
