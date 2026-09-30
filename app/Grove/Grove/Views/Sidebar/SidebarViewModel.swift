// Views/Sidebar/SidebarViewModel.swift
// Grove

import Foundation
import Observation

/// ViewModel for the in-repository sidebar.
///
/// Manages branch, remote, tag lists and the current navigation selection.
@MainActor
@Observable
final class SidebarViewModel {

    // MARK: - State

    var selection: SidebarItem? = .workingCopy
    /// Shared with the session's other views, so the sidebar never reads refs on its own.
    let refs: RepositoryRefs
    var localBranches: [BranchInfo] { refs.localBranches }
    var remoteBranches: [BranchInfo] { refs.remoteBranches }
    var tags: [TagInfo] { refs.tags }
    var remotes: [RemoteInfo] { refs.remotes }
    var worktrees: [WorktreeInfo] { refs.worktrees }
    var submodules: [SubmoduleInfo] { refs.submodules }
    var isLoading: Bool { refs.isRefreshing }

    /// A failed action, else a failed ref read.
    var errorMessage: String? {
        get { actionError ?? refs.errorMessage }
        set {
            actionError = newValue
            if newValue == nil { refs.dismissError() }
        }
    }
    private var actionError: String?

    /// Changed-file count shown on the Changes badge.
    var workingCopyBadgeCount: Int { changeCountSource?() ?? refs.changedCount }
    /// Set by the session to count from the Changes list instead of a second status read.
    var changeCountSource: (() -> Int)?

    /// Worktrees other than the one this window shows; from a linked worktree that includes the main one.
    var otherWorktrees: [WorktreeInfo] {
        worktrees.filter { !isCurrent($0) }
    }

    func isCurrent(_ worktree: WorktreeInfo) -> Bool {
        WorktreeResolver.isSameFolder(worktree.path, repository.path.path)
    }

    /// The other worktree that has `branch` checked out; git won't check it out here too.
    func worktree(checkingOut branch: BranchInfo) -> WorktreeInfo? {
        otherWorktrees.first { $0.branch == branch.name }
    }

    /// Set by the window: moves it to another worktree of this repository, where git commands then run.
    var onSwitchWorktree: ((String) -> Void)?

    func switchTo(_ worktree: WorktreeInfo) {
        guard !worktree.isPrunable, !isCurrent(worktree) else { return }
        onSwitchWorktree?(worktree.path)
    }

    /// Set by the window: opens another worktree in a new tab, or focuses the tab already showing it.
    var onOpenWorktreeInNewTab: ((String) -> Void)?

    /// Set by the window: a removed worktree's path, then the main worktree's, so tabs showing it can move.
    var onWorktreeRemoved: ((String, String?) -> Void)?

    func openInNewTab(_ worktree: WorktreeInfo) {
        guard !worktree.isPrunable, !isCurrent(worktree) else { return }
        onOpenWorktreeInNewTab?(worktree.path)
    }

    /// Set by the session: selects a SHA in History, or opens the given ref's own history when HEAD's lacks it.
    var onRevealInHistory: ((String, SidebarItem) -> Void)?

    func revealInHistory(_ item: SidebarItem) {
        switch item {
        case .branch(let branch), .remoteBranch(let branch): onRevealInHistory?(branch.targetSHA, item)
        case .tag(let tag): onRevealInHistory?(tag.targetSHA, item)
        default: break
        }
    }

    /// Double-click on a branch: open the worktree that has it in a new tab, otherwise check it out here.
    func activate(branch: BranchInfo) async {
        if let worktree = worktree(checkingOut: branch) {
            openInNewTab(worktree)
        } else if !branch.isHEAD {
            await checkout(branch: branch)
        }
    }

    func select(_ item: SidebarItem) {
        selection = item
    }

    /// Set by the session, which owns the Create Pull Request sheet.
    var onCreatePullRequest: ((String) -> Void)?

    /// Local branches open as themselves; remote ones by their name on the remote.
    func createPullRequest(for branch: BranchInfo) {
        onCreatePullRequest?(branch.isRemote ? Self.shortName(of: branch) : branch.name)
    }

    /// Dropping on Changes: `stash@{N}` applies a stash, a SHA cherry-picks,
    /// a branch merges (or rebases when `rebase` is set, i.e. Option held).
    func handleWorkingCopyDrop(_ payload: String, rebase: Bool) -> Bool {
        if payload.hasPrefix("stash@{"), payload.hasSuffix("}"),
           let index = Int(payload.dropFirst("stash@{".count).dropLast()) {
            Task { await stashApply(index: index) }
            return true
        }
        let isHex = payload.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
        if isHex && payload.count >= 7 {
            Task { await cherryPick(sha: payload) }
            return true
        }
        guard let branch = localBranches.first(where: { $0.name == payload }) else { return false }
        Task {
            if rebase { await self.rebase(onto: branch) } else { await merge(branch: branch) }
        }
        return true
    }

    // MARK: - Pinned Branches

    /// Branch names that are pinned to the top of the sidebar.
    var pinnedBranchNames: Set<String> = []

    /// Local branches whose names appear in ``pinnedBranchNames``, sorted alphabetically.
    var pinnedBranches: [BranchInfo] {
        localBranches
            .filter { pinnedBranchNames.contains($0.name) && !archivedBranchNames.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Toggle a branch between pinned and unpinned.
    func togglePin(branch: BranchInfo) {
        if pinnedBranchNames.contains(branch.name) {
            pinnedBranchNames.remove(branch.name)
        } else {
            pinnedBranchNames.insert(branch.name)
        }
        savePinnedBranches()
    }

    // MARK: - Stacks

    var stacks: [BranchStack] { refs.stacks }
    /// Opens the Stack tab on the stack holding a branch; the session wires it to the Stack view model.
    var onShowStack: ((String) -> Void)?

    func showStack(containing branch: String) {
        onShowStack?(branch)
        select(.stack)
    }

    /// Layers of a stack, which Branches lists under their stack instead of by name.
    var stackedBranchNames: Set<String> {
        Set(refs.stacks.flatMap { $0.layers.map(\.branch) }).subtracting(archivedBranchNames)
    }

    // MARK: - Archived Branches

    /// Branches the user archived: hidden from Branches, listed under Archived.
    var archivedBranchNames: Set<String> = []

    var archivedBranches: [BranchInfo] {
        localBranches.filter { archivedBranchNames.contains($0.name) }.sorted { $0.name < $1.name }
    }

    func archive(branch: BranchInfo) {
        archivedBranchNames.insert(branch.name)
        pinnedBranchNames.remove(branch.name)
        UserDefaults.standard.set(Array(archivedBranchNames), forKey: archivedBranchesDefaultsKey)
        savePinnedBranches()
    }

    func unarchive(branch: BranchInfo) {
        archivedBranchNames.remove(branch.name)
        UserDefaults.standard.set(Array(archivedBranchNames), forKey: archivedBranchesDefaultsKey)
    }

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    /// Set by the session so a sidebar mutation refreshes every view, not just the sidebar.
    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?
    /// Set by the session so flow branches offer Finish in their context menu.
    var gitFlow: GitFlowViewModel?

    /// Call after anything that changed refs or the working tree.
    func didChangeRepository() async {
        if let onRepositoryChanged { await onRepositoryChanged() } else { await refresh() }
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Private

    private var pinnedBranchesDefaultsKey: String {
        BranchPins.key(forRepositoryAt: repository.path.path)
    }

    private var archivedBranchesDefaultsKey: String {
        "grove.archivedBranches.\(repository.path.path)"
    }

    // MARK: - Init

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs? = nil) {
        self.repository = repository
        self.refs = refs ?? RepositoryRefs(repository: repository)
        loadPinnedBranches()
    }

    // MARK: - Pinned Branches Persistence

    private func loadPinnedBranches() {
        let saved = UserDefaults.standard.stringArray(forKey: pinnedBranchesDefaultsKey) ?? []
        pinnedBranchNames = Set(saved)
        archivedBranchNames = Set(UserDefaults.standard.stringArray(forKey: archivedBranchesDefaultsKey) ?? [])
    }

    private func savePinnedBranches() {
        UserDefaults.standard.set(Array(pinnedBranchNames), forKey: pinnedBranchesDefaultsKey)
    }

    // MARK: - Actions

    func refresh() async {
        await refs.refresh()
        // The New Branch dialog can pin a branch it creates.
        pinnedBranchNames = BranchPins.names(forRepositoryAt: repository.path.path)
    }

    /// The session normally loads refs first; this only covers a sidebar shown on its own, e.g. in previews.
    func loadIfNeeded() async {
        await refs.loadIfNeeded()
    }

    func checkout(branch: BranchInfo) async {
        let previous = localBranches.first(where: \.isHEAD)?.name
        do {
            try await repository.checkout(branch: branch.name)
            recordCheckout(of: branch.name, from: previous)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks out a remote branch as a local tracking branch (git's DWIM),
    /// or the existing local branch of the same name.
    func checkout(remoteBranch branch: BranchInfo) async {
        let localName = Self.shortName(of: branch)
        let previous = localBranches.first(where: \.isHEAD)?.name
        do {
            try await repository.checkout(branch: localName)
            recordCheckout(of: localName, from: previous)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteBranch(_ branch: BranchInfo, force: Bool = false) async {
        do {
            try await repository.deleteBranch(name: branch.name, force: force)
            recordBranchDeletion(branch)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Detached HEAD has no branch to return to, so it isn't recorded.
    private func recordCheckout(of target: String, from previous: String?) {
        guard let previous, previous != target else { return }
        undoManager?.record(GitUndoManager.checkoutAction(targetBranch: target, previousBranch: previous,
                                                          repository: repository))
    }

    /// Also called by the delete dialog, which deletes the branch itself.
    func recordBranchDeletion(_ branch: BranchInfo) {
        undoManager?.record(GitUndoManager.deleteBranchAction(branchName: branch.name, sha: branch.targetSHA,
                                                              repository: repository))
    }

    /// Merges `branch` into the current HEAD.
    func merge(branch: BranchInfo) async {
        do {
            try await repository.merge(branch: branch.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rebases the current HEAD onto `branch`.
    func rebase(onto branch: BranchInfo) async {
        do {
            try await repository.rebase(onto: branch.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cherry-picks the commit identified by `sha` onto HEAD.
    ///
    /// Called when a commit SHA is dropped onto the Working Copy sidebar item.
    func cherryPick(sha: String) async {
        do {
            try await repository.cherryPick(commit: sha)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the stash at `index` without dropping it from the stash list.
    ///
    /// Called when a stash entry is dropped onto the Working Copy sidebar item.
    func stashApply(index: Int) async {
        do {
            try await repository.stashApply(index: index, drop: false)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a tag.
    func deleteTag(_ tag: TagInfo) async {
        do {
            try await repository.deleteTag(name: tag.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a remote-tracking branch on the remote.
    func deleteRemoteBranch(_ branch: BranchInfo) async {
        guard let remote = branch.remoteName else { return }
        do {
            try await repository.deleteRemoteBranch(name: Self.shortName(of: branch), remote: remote)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Submodules (actions in SidebarViewModel+Submodules.swift)

    /// A running submodule action, e.g. "Cloning vendor/icons…", shown under the sidebar.
    private(set) var activity: String?
    private(set) var isAddingSubmodule = false
    private(set) var isAddingRemote = false

    // MARK: - Drops (SidebarViewModel+Drops.swift)

    /// A drop waiting for confirmation, e.g. merging one branch into another.
    var pendingDrop: SidebarDropAction?
    var dropError: String?
    var isRunningDrop = false

    func requestAddSubmodule() { isAddingSubmodule = true }
    /// The worktree the Remove Worktree sheet is for; the sidebar owns the sheet since the section can vanish.
    private(set) var worktreePendingRemoval: WorktreeInfo?
    func requestRemoval(of worktree: WorktreeInfo) { worktreePendingRemoval = worktree }
    func dismissWorktreeRemoval() { worktreePendingRemoval = nil }
    func dismissAddSubmodule() { isAddingSubmodule = false }
    func requestAddRemote() { isAddingRemote = true }
    func dismissAddRemote() { isAddingRemote = false }

    /// Runs a git mutation with `title` showing, then refreshes every view.
    func perform(_ title: String, _ work: () async throws -> Void) async {
        activity = title
        defer { activity = nil }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await didChangeRepository()
    }

    func pruneWorktrees() async {
        do {
            try await repository.pruneWorktrees()
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Remote branch name without its "remote/" prefix.
    static func shortName(of branch: BranchInfo) -> String {
        if let remote = branch.remoteName, branch.name.hasPrefix(remote + "/") {
            return String(branch.name.dropFirst(remote.count + 1))
        }
        return branch.name
    }

    /// Branch groups derived from "/" in branch names.
    var localBranchGroups: [(prefix: String?, branches: [BranchInfo])] {
        var ungrouped: [BranchInfo] = []
        var groups: [String: [BranchInfo]] = [:]

        let stacked = stackedBranchNames
        for branch in localBranches where !archivedBranchNames.contains(branch.name) && !stacked.contains(branch.name) {
            if let slashIndex = branch.name.firstIndex(of: "/") {
                let prefix = String(branch.name[branch.name.startIndex..<slashIndex])
                groups[prefix, default: []].append(branch)
            } else {
                ungrouped.append(branch)
            }
        }

        var result: [(prefix: String?, branches: [BranchInfo])] = []
        result.append((prefix: nil, branches: ungrouped))
        for key in groups.keys.sorted() {
            result.append((prefix: key, branches: groups[key]!))
        }
        return result
    }

    /// Remote branches grouped by their remote name.
    var remoteBranchGroups: [String: [BranchInfo]] {
        Dictionary(grouping: remoteBranches) { $0.remoteName ?? "origin" }
    }
}
