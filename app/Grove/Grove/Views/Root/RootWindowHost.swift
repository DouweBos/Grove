// Views/Root/RootWindowHost.swift
// Grove
//
// Single window host with a permanent NavigationSplitView.
// The sidebar transitions between the repository browser and
// in-repository navigation. The detail pane shows either the
// browser content or the active repository's content.

import SwiftUI
import AppKit
import os

// MARK: - CachedSession

/// Pairs a loaded repository handle with its session so both can be
/// cached together by path.
private struct CachedSession {
    let repository: any GitRepositoryProtocol
    let session: RepositorySession
}

// MARK: - RootWindowHost

struct RootWindowHost: View {

    let manager: any RepositoryManagerProtocol

    // MARK: Navigation State

    /// Current repo shown. nil = browser.
    @State private var openRepo: RepositoryReference?

    // MARK: Tab State (only active after Cmd+T)

    @State private var tabs: [RepositoryReference] = []
    @State private var selectedTabIndex: Int = 0

    // MARK: ViewModels & Sessions

    @State private var browserVM: RepositoryBrowserViewModel

    /// Loaded repositories and their sessions, keyed by filesystem path.
    @State private var sessions: [String: CachedSession] = [:]

    /// Repo paths that failed to open.
    @State private var repoErrors: [String: String] = [:]

    // MARK: Split View

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        self._browserVM = State(initialValue: RepositoryBrowserViewModel(manager: manager))
    }

    // MARK: Computed

    private var isBrowser: Bool { openRepo == nil }

    private var currentCached: CachedSession? {
        guard let ref = openRepo else { return nil }
        return sessions[ref.path]
    }

    // MARK: Body

    var body: some View {
        @Bindable var bvm = browserVM

        VStack(spacing: 0) {
            // Tab bar — only when Cmd+T has been used and 2+ repos are open
            if tabs.count > 1 {
                TabBarView(
                    tabs: tabs,
                    selectedIndex: selectedTabIndex,
                    onSelect: { index in
                        selectedTabIndex = clamp(index)
                        openRepo = tabs[selectedTabIndex]
                    },
                    onClose: { index in
                        closeTab(at: index)
                    },
                    onNewTab: {
                        openRepo = nil
                    }
                )
            }

            // Single permanent NavigationSplitView
            NavigationSplitView(columnVisibility: $columnVisibility) {
                UnifiedSidebar(session: currentCached?.session)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
            } detail: {
                detailContent
            }
            .navigationTitle(openRepo?.displayName ?? "Grove")
        }
        .frame(minWidth: 900, minHeight: 600)
        .environment(browserVM)
        .toolbar { toolbarContent }
        // Browser navigation
        .onChange(of: browserVM.pendingOpenRef) { _, ref in
            guard let ref else { return }
            browserVM.pendingOpenRef = nil
            navigateToRepo(ref)
        }
        // Load session when openRepo changes
        .onChange(of: openRepo) { _, ref in
            if let ref {
                loadSessionIfNeeded(for: ref)
            }
        }
        // Column visibility ↔ sourceMode sync (browser only)
        .onChange(of: columnVisibility) { _, newVisibility in
            if isBrowser {
                if newVisibility == .detailOnly {
                    browserVM.sourceMode = .none
                } else if browserVM.sourceMode == .none {
                    browserVM.sourceMode = .local
                }
            }
        }
        .onChange(of: browserVM.sourceMode) { oldMode, newMode in
            if isBrowser && oldMode == .none && newMode != .none && columnVisibility == .detailOnly {
                columnVisibility = .all
            }
        }
        // Tab keyboard shortcuts
        .onReceive(
            NotificationCenter.default.publisher(for: GroveTabAction.notificationName)
        ) { notification in
            guard let action = GroveTabAction(notification: notification) else { return }
            handleTabAction(action)
        }
        // Repository actions → forward to active session
        .onReceive(
            NotificationCenter.default.publisher(for: GroveAction.notificationName)
        ) { notification in
            guard let action = GroveAction(notification: notification) else { return }
            currentCached?.session.handleAction(action)
        }
        .onDisappear {
            for (_, cached) in sessions {
                cached.session.stop()
            }
        }
        // Browser sheets
        .sheet(isPresented: $bvm.isShowingCloneDialog) {
            CloneDialogView()
                .environment(browserVM)
        }
        .sheet(isPresented: $bvm.isShowingAddDialog) {
            AddRepositorySheet()
                .environment(browserVM)
        }
        .sheet(isPresented: $bvm.isShowingCreateDialog) {
            CreateRepositorySheet()
                .environment(browserVM)
        }
    }

    // MARK: Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let ref = openRepo {
            if let cached = currentCached {
                RepositoryContentRouter(session: cached.session, repository: cached.repository)
                    .repositoryToolbar(repository: cached.repository, state: cached.session.toolbarState)
                    .environment(cached.session.gitUndoManager)
                    .focusedValue(\.gitUndoManager, cached.session.gitUndoManager)
                    .id(ref.path)
            } else if let error = repoErrors[ref.path] {
                ContentUnavailableView(
                    "Cannot Open Repository",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("Opening repository\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            RepositoryBrowserContent()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isBrowser {
            ToolbarItem(placement: .navigation) {
                Button {
                    openRepo = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back to Repositories")
            }
        }
    }

    // MARK: Session Loading

    private func loadSessionIfNeeded(for ref: RepositoryReference) {
        let path = ref.path
        guard sessions[path] == nil, repoErrors[path] == nil else { return }
        Logger.ui.info("Opening repository for \(path, privacy: .public)")
        Task {
            let url = URL(fileURLWithPath: path)
            do {
                let repo = try await GitRepository(path: url)
                let session = RepositorySession(repository: repo)
                sessions[path] = CachedSession(repository: repo, session: session)
                await session.start()
                Logger.ui.info("Repository ready: \(ref.displayName, privacy: .public)")
            } catch {
                Logger.ui.error("Failed to open repository \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                repoErrors[path] = error.localizedDescription
            }
        }
    }

    // MARK: Navigation

    private func navigateToRepo(_ ref: RepositoryReference) {
        openRepo = ref
        if !tabs.isEmpty {
            if !tabs.contains(where: { $0.path == ref.path }) {
                tabs.append(ref)
            }
            selectedTabIndex = tabs.firstIndex(where: { $0.path == ref.path }) ?? 0
        }
    }

    // MARK: Tab Actions

    private func handleTabAction(_ action: GroveTabAction) {
        switch action {
        case .newTab:
            if tabs.isEmpty, let current = openRepo {
                tabs = [current]
                selectedTabIndex = 0
            }
            openRepo = nil

        case .closeTab:
            if tabs.count > 1 {
                closeTab(at: selectedTabIndex)
            } else if !tabs.isEmpty {
                tabs.removeAll()
            } else if openRepo != nil {
                openRepo = nil
            } else {
                NSApplication.shared.keyWindow?.close()
            }

        case .closeWindow:
            NSApplication.shared.keyWindow?.close()

        case .nextTab:
            guard tabs.count > 1 else { return }
            selectedTabIndex = (selectedTabIndex + 1) % tabs.count
            openRepo = tabs[selectedTabIndex]

        case .previousTab:
            guard tabs.count > 1 else { return }
            selectedTabIndex = (selectedTabIndex - 1 + tabs.count) % tabs.count
            openRepo = tabs[selectedTabIndex]
        }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if tabs.count == 1 {
            let remaining = tabs.removeFirst()
            openRepo = remaining
        } else if tabs.isEmpty {
            openRepo = nil
        } else {
            selectedTabIndex = min(selectedTabIndex, tabs.count - 1)
            openRepo = tabs[selectedTabIndex]
        }
    }

    private func clamp(_ index: Int) -> Int {
        guard !tabs.isEmpty else { return 0 }
        return max(0, min(index, tabs.count - 1))
    }
}

#Preview {
    RootWindowHost(manager: MockRepositoryManager())
}
