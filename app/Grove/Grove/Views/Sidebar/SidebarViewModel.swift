// Views/Sidebar/SidebarViewModel.swift
// Grove

import Foundation
import GroveKit
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

    /// Branch, remote, submodule and worktree actions, shared with GroveKit's other apps.
    let actions: RefActionsViewModel

    /// A failed action, else a failed ref read.
    var errorMessage: String? {
        get { actionError ?? actions.errorMessage ?? refs.errorMessage }
        set {
            actionError = newValue
            if newValue == nil {
                actions.dismissError()
                refs.dismissError()
            }
        }
    }
    private var actionError: String?

    /// Changed-file count shown on the Changes badge.
    var workingCopyBadgeCount: Int { changeCountSource?() ?? refs.changedCount }
    /// Set by the session to count from the Changes list instead of a second status read.
    var changeCountSource: (() -> Int)?

    /// Set by the window: moves it to another worktree of this repository, where git commands then run.
    var onSwitchWorktree: ((String) -> Void)?

    func switchTo(_ worktree: WorktreeInfo) {
        guard !worktree.isPrunable, !actions.isCurrent(worktree) else { return }
        onSwitchWorktree?(worktree.path)
    }

    /// Set by the window: opens another worktree in a new tab, or focuses the tab already showing it.
    var onOpenWorktreeInNewTab: ((String) -> Void)?

    func openInNewTab(_ worktree: WorktreeInfo) {
        guard !worktree.isPrunable, !actions.isCurrent(worktree) else { return }
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
        if let worktree = actions.worktree(checkingOut: branch) {
            openInNewTab(worktree)
        } else if !branch.isHEAD {
            await actions.checkout(branch: branch)
        }
    }

    func select(_ item: SidebarItem) {
        selection = item
    }

    /// Set by the session, which owns the Create Pull Request sheet.
    var onCreatePullRequest: ((String) -> Void)?

    /// Local branches open as themselves; remote ones by their name on the remote.
    func createPullRequest(for branch: BranchInfo) {
        onCreatePullRequest?(branch.isRemote ? RefActionsViewModel.shortName(of: branch) : branch.name)
    }

    /// Set by the session, which owns the Actions tab.
    var onShowRuns: ((String) -> Void)?

    /// Opens the Actions tab filtered to the branch, by its name on the remote.
    func showRuns(for branch: BranchInfo) {
        onShowRuns?(branch.isRemote ? RefActionsViewModel.shortName(of: branch) : branch.name)
    }

    /// Dropping on Changes: `stash@{N}` applies a stash, a SHA cherry-picks,
    /// a branch merges (or rebases when `rebase` is set, i.e. Option held).
    func handleWorkingCopyDrop(_ payload: String, rebase: Bool) -> Bool {
        if payload.hasPrefix("stash@{"), payload.hasSuffix("}"),
           let index = Int(payload.dropFirst("stash@{".count).dropLast()) {
            Task { await actions.stashApply(index: index) }
            return true
        }
        let isHex = payload.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
        if isHex && payload.count >= 7 {
            Task { await actions.cherryPick(sha: payload) }
            return true
        }
        guard let branch = localBranches.first(where: { $0.name == payload }) else { return false }
        Task {
            if rebase { await actions.rebase(onto: branch) } else { await actions.merge(branch: branch) }
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
    func showStack(_ stack: BranchStack) {
        select(.branchStack(stack.id))
    }

    func showStack(containing branch: String) {
        guard let stack = refs.stack(containing: branch) else { return }
        showStack(stack)
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
    var onRepositoryChanged: (() async -> Void)? {
        get { actions.onRepositoryChanged }
        set { actions.onRepositoryChanged = newValue }
    }
    var undoManager: GitUndoManager? {
        get { actions.undoManager }
        set { actions.undoManager = newValue }
    }
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
        let refs = refs ?? RepositoryRefs(repository: repository)
        self.refs = refs
        self.actions = RefActionsViewModel(repository: repository, refs: refs)
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

    // MARK: - Sheets

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

    // MARK: - Derived

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
