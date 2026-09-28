// Views/Toolbar/RepositoryToolbar.swift
// Grove
//
// Toolbar items for repository windows: Fetch, Pull, Push, Branch, Tag.
// Sheet presentations live in RepositoryToolbarView (a thin wrapper view)
// so that .sheet() modifiers can attach to a View, not ToolbarContent.

import SwiftUI
import Observation

// MARK: - RepositoryToolbarState

/// Observable state for the repository toolbar sheet presentations. Owned by the session.
@MainActor
@Observable
final class RepositoryToolbarState {
    var isPushPresented = false
    var isPullPresented = false
    var isFetchPresented = false
    var isSyncPresented = false
    var isBranchPresented = false
    var isTagPresented = false
    var isStashPresented = false
    var isMergePresented = false
    var isRebasePresented = false
    var isFetching = false
    var isSyncing = false

    /// Sheets read branches and remotes from here, so they open without waiting for git.
    let refs: RepositoryRefs
    let gitFlow: GitFlowViewModel
    /// Set by the session: the Add Submodule sheet lives with the sidebar's submodules.
    var onAddSubmodule: (() -> Void)?

    init(refs: RepositoryRefs, gitFlow: GitFlowViewModel) {
        self.refs = refs
        self.gitFlow = gitFlow
    }

    enum Sheet { case fetch, pull, push, sync, branch, tag, stash, merge, rebase }

    /// Shows the sheet at once with the last-read refs, reading them first only if they never loaded.
    func present(_ sheet: Sheet) {
        switch sheet {
        case .fetch: isFetchPresented = true
        case .pull: isPullPresented = true
        case .push: isPushPresented = true
        case .sync: isSyncPresented = true
        case .branch: isBranchPresented = true
        case .tag: isTagPresented = true
        case .stash: isStashPresented = true
        case .merge: isMergePresented = true
        case .rebase: isRebasePresented = true
        }
        if !refs.hasLoaded { Task { await refs.loadIfNeeded() } }
    }
}

// MARK: - RepositoryToolbar

/// `ToolbarContent` declaring the repository action buttons.
///
/// Sheet presentations are handled by `RepositoryToolbarSheets` — a thin
/// wrapping view that uses `@Bindable` to project bindings from the
/// shared `RepositoryToolbarState`.
struct RepositoryToolbar: ToolbarContent {

    let repository: any GitRepositoryProtocol
    let toolbarState: RepositoryToolbarState
    let selection: SidebarItem?
    let changeCount: Int
    var iconsOnly = false
    let onNavigate: (SidebarItem) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            PillTabBar(
                tabs: visibleTabs.map {
                    PillTab(id: $0, title: $0.title, symbol: $0.symbol, badge: $0 == .changes ? changeCount : nil)
                },
                selection: currentTab,
                compact: true,
                iconsOnly: iconsOnly
            ) { onNavigate($0.item) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            fetchButton
            pullButton
            pushButton
            syncButton
        }
        ToolbarItem(placement: .primaryAction) {
            RepositoryMoreMenu(toolbarState: toolbarState, onNavigate: onNavigate)
        }
    }

    private var currentTab: RepositoryTab? {
        selection.map(RepositoryTab.init(item:))
    }

    private var visibleTabs: [RepositoryTab] {
        guard let currentTab, RepositoryTab.secondary.contains(currentTab) else { return RepositoryTab.primary }
        return RepositoryTab.primary + [currentTab]
    }

    // MARK: Sync

    private var syncButton: some View {
        Button {
            toolbarState.present(.sync)
        } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Sync: fetch, pull, then push")
        .disabled(toolbarState.isSyncing)
    }

    // MARK: Fetch

    private var fetchButton: some View {
        Button {
            toolbarState.present(.fetch)
        } label: {
            Label("Fetch", systemImage: "arrow.clockwise")
        }
        .help("Fetch from remote")
    }

    // MARK: Pull

    private var pullButton: some View {
        Button {
            toolbarState.present(.pull)
        } label: {
            Label("Pull", systemImage: "arrow.down.to.line")
        }
        .help("Pull from remote")
    }

    // MARK: Push

    private var pushButton: some View {
        Button {
            toolbarState.present(.push)
        } label: {
            Label("Push", systemImage: "arrow.up.to.line")
        }
        .help("Push to remote")
    }

}

// MARK: - RepositoryToolbarSheets

/// Thin `View` wrapper that attaches toolbar items and all associated sheets.
///
/// Using a dedicated `View` (rather than a `View` extension with closures)
/// lets us use `@Bindable` to project bindings from ``RepositoryToolbarState``.
struct RepositoryToolbarSheets<Content: View>: View {

    @Bindable var toolbarState: RepositoryToolbarState
    let repository: any GitRepositoryProtocol
    let sidebarVM: SidebarViewModel
    /// Called after a dialog changed the repository so every view reloads.
    let onComplete: () -> Void
    let content: Content

    init(
        toolbarState: RepositoryToolbarState,
        repository: any GitRepositoryProtocol,
        sidebarVM: SidebarViewModel,
        onComplete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.toolbarState = toolbarState
        self.repository = repository
        self.sidebarVM = sidebarVM
        self.onComplete = onComplete
        self.content = content()
    }

    @State private var isNarrow = false

    private var refs: RepositoryRefs { toolbarState.refs }

    var body: some View {
        content
            // Titled pills plus the remote actions need ~760pt; below that the toolbar would overflow.
            .onGeometryChange(for: Bool.self) { $0.size.width < 760 } action: { isNarrow = $0 }
            .toolbar {
                RepositoryToolbar(
                    repository: repository,
                    toolbarState: toolbarState,
                    selection: sidebarVM.selection,
                    changeCount: sidebarVM.workingCopyBadgeCount,
                    iconsOnly: isNarrow
                ) { sidebarVM.select($0) }
            }
            .sheet(isPresented: $toolbarState.isPushPresented) {
                PushDialogView(repository: repository, refs: refs, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isPullPresented) {
                PullDialogView(repository: repository, refs: refs, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isFetchPresented) {
                FetchDialogView(repository: repository, remotes: refs.remotes, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isSyncPresented) {
                SyncDialogView(repository: repository, remotes: refs.remotes, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isBranchPresented) {
                CreateBranchDialogView(repository: repository, localBranches: refs.localBranches) { _ in onComplete() }
            }
            .sheet(isPresented: $toolbarState.isTagPresented) {
                CreateTagDialogView(repository: repository) { _ in onComplete() }
            }
            .sheet(isPresented: $toolbarState.isStashPresented) {
                StashDialogView(repository: repository, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isMergePresented) {
                MergeDialogView(repository: repository, localBranches: refs.localBranches, onComplete: onComplete)
            }
            .sheet(isPresented: $toolbarState.isRebasePresented) {
                RebaseDialogView(repository: repository, localBranches: refs.localBranches, onComplete: onComplete)
            }
            .sheet(item: Binding(get: { toolbarState.gitFlow.sheet },
                                 set: { if $0 == nil { toolbarState.gitFlow.dismissSheet() } })) { sheet in
                GitFlowSheetView(viewModel: toolbarState.gitFlow, sheet: sheet)
            }
    }
}

// MARK: - View+repositoryToolbar

extension View {

    /// Wraps the view with repository toolbar buttons and their sheets.
    func repositoryToolbar(
        repository: any GitRepositoryProtocol,
        state: RepositoryToolbarState,
        sidebarVM: SidebarViewModel,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        RepositoryToolbarSheets(toolbarState: state, repository: repository, sidebarVM: sidebarVM, onComplete: onComplete) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    let repo = MockGitRepository()
    let refs = RepositoryRefs(repository: repo)
    let state = RepositoryToolbarState(refs: refs, gitFlow: GitFlowViewModel(repository: repo, refs: refs))
    return NavigationStack {
        Text("Repository Content")
            .frame(width: 800, height: 600)
            .repositoryToolbar(repository: repo, state: state, sidebarVM: SidebarViewModel(repository: repo))
    }
}
