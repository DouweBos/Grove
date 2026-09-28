// Views/Toolbar/RepositoryToolbar.swift
// Grove
//
// Toolbar items for repository windows: Fetch, Pull, Push, Branch, Tag.
// Sheet presentations live in RepositoryToolbarView (a thin wrapper view)
// so that .sheet() modifiers can attach to a View, not ToolbarContent.

import SwiftUI
import Observation

// MARK: - RepositoryToolbarState

/// Observable state for the repository toolbar sheet presentations.
///
/// Owned as `@State` in the hosting view so SwiftUI tracks changes.
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

    var localBranches: [BranchInfo] = []
    var remoteBranches: [BranchInfo] = []
    var remotes: [RemoteInfo] = []
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
    let onNavigate: (SidebarItem) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            PillTabBar(
                tabs: visibleTabs.map {
                    PillTab(id: $0, title: $0.title, symbol: $0.symbol, badge: $0 == .changes ? changeCount : nil)
                },
                selection: currentTab,
                compact: true
            ) { onNavigate($0.item) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            fetchButton
            pullButton
            pushButton
            syncButton
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(RepositoryTab.secondary, id: \.self) { tab in
                    Button {
                        onNavigate(tab.item)
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                }
                Divider()
                Button {
                    toolbarState.isStashPresented = true
                } label: {
                    Label("Stash Changes…", systemImage: "tray.and.arrow.down")
                }
                Divider()
                Button {
                    Task {
                        toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                        toolbarState.isBranchPresented = true
                    }
                } label: {
                    Label("New Branch…", systemImage: "arrow.triangle.branch")
                }
                Button {
                    toolbarState.isTagPresented = true
                } label: {
                    Label("New Tag…", systemImage: "tag")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
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
            Task {
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isSyncPresented = true
            }
        } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Sync: fetch, pull, then push")
        .disabled(toolbarState.isSyncing)
    }

    // MARK: Fetch

    private var fetchButton: some View {
        Button {
            Task {
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isFetchPresented = true
            }
        } label: {
            Label("Fetch", systemImage: "arrow.clockwise")
        }
        .help("Fetch from remote")
    }

    // MARK: Pull

    private var pullButton: some View {
        Button {
            Task {
                toolbarState.remoteBranches = (try? await repository.remoteBranches()) ?? []
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isPullPresented = true
            }
        } label: {
            Label("Pull", systemImage: "arrow.down.to.line")
        }
        .help("Pull from remote")
    }

    // MARK: Push

    private var pushButton: some View {
        Button {
            Task {
                toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isPushPresented = true
            }
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
    let content: Content

    init(
        toolbarState: RepositoryToolbarState,
        repository: any GitRepositoryProtocol,
        sidebarVM: SidebarViewModel,
        @ViewBuilder content: () -> Content
    ) {
        self.toolbarState = toolbarState
        self.repository = repository
        self.sidebarVM = sidebarVM
        self.content = content()
    }

    var body: some View {
        content
            .toolbar {
                RepositoryToolbar(
                    repository: repository,
                    toolbarState: toolbarState,
                    selection: sidebarVM.selection,
                    changeCount: sidebarVM.workingCopyBadgeCount
                ) { sidebarVM.select($0) }
            }
            .sheet(isPresented: $toolbarState.isPushPresented) {
                PushDialogView(
                    repository: repository,
                    branches: toolbarState.localBranches,
                    remotes: toolbarState.remotes
                )
            }
            .sheet(isPresented: $toolbarState.isPullPresented) {
                PullDialogView(
                    repository: repository,
                    remoteBranches: toolbarState.remoteBranches,
                    remotes: toolbarState.remotes
                )
            }
            .sheet(isPresented: $toolbarState.isFetchPresented) {
                FetchDialogView(
                    repository: repository,
                    remotes: toolbarState.remotes
                )
            }
            .sheet(isPresented: $toolbarState.isSyncPresented) {
                SyncDialogView(
                    repository: repository,
                    remotes: toolbarState.remotes
                )
            }
            .sheet(isPresented: $toolbarState.isBranchPresented) {
                CreateBranchDialogView(
                    repository: repository,
                    localBranches: toolbarState.localBranches
                )
            }
            .sheet(isPresented: $toolbarState.isTagPresented) {
                CreateTagDialogView(repository: repository)
            }
            .sheet(isPresented: $toolbarState.isStashPresented) {
                StashDialogView(repository: repository)
            }
            .sheet(isPresented: $toolbarState.isMergePresented) {
                MergeDialogView(
                    repository: repository,
                    localBranches: toolbarState.localBranches
                )
            }
            .sheet(isPresented: $toolbarState.isRebasePresented) {
                RebaseDialogView(
                    repository: repository,
                    localBranches: toolbarState.localBranches
                )
            }
    }
}

// MARK: - View+repositoryToolbar

extension View {

    /// Wraps the view with repository toolbar buttons and their sheets.
    func repositoryToolbar(
        repository: any GitRepositoryProtocol,
        state: RepositoryToolbarState,
        sidebarVM: SidebarViewModel
    ) -> some View {
        RepositoryToolbarSheets(toolbarState: state, repository: repository, sidebarVM: sidebarVM) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    let repo = MockGitRepository()
    let state = RepositoryToolbarState()
    return NavigationStack {
        Text("Repository Content")
            .frame(width: 800, height: 600)
            .repositoryToolbar(repository: repo, state: state, sidebarVM: SidebarViewModel(repository: repo))
    }
}
