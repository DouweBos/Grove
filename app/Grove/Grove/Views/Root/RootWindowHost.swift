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

// MARK: - RootWindowHost

struct RootWindowHost: View {

    let manager: any RepositoryManagerProtocol

    // MARK: ViewModels

    @State private var windowVM: WindowViewModel

    // MARK: Split View

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        self._windowVM = State(initialValue: WindowViewModel(manager: manager))
    }

    // MARK: Body

    var body: some View {
        @Bindable var vm = windowVM

        NavigationSplitView(columnVisibility: $columnVisibility) {
            UnifiedSidebar(session: windowVM.currentSession?.session)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            detailContent
        }
        .navigationTitle(windowVM.openRepo?.displayName ?? "Grove")
        .frame(minWidth: 900, minHeight: 600)
        .environment(windowVM)
        .toolbar { toolbarContent }
        // Load session when openRepo changes
        .onChange(of: windowVM.openRepo) { _, ref in
            if let ref {
                windowVM.loadSessionIfNeeded(for: ref)
            }
        }
        // Column visibility ↔ sourceMode sync (browser only)
        .onChange(of: columnVisibility) { _, newVisibility in
            if windowVM.isBrowsing {
                if newVisibility == .detailOnly {
                    windowVM.setSourceMode(.none)
                } else if windowVM.sourceMode == .none {
                    windowVM.setSourceMode(.local)
                }
            }
        }
        .onChange(of: windowVM.sourceMode) { oldMode, newMode in
            if windowVM.isBrowsing && oldMode == .none && newMode != .none && columnVisibility == .detailOnly {
                columnVisibility = .all
            }
        }
        // Repository actions → forward to active session
        .onReceive(
            NotificationCenter.default.publisher(for: GroveAction.notificationName)
        ) { notification in
            guard let action = GroveAction(notification: notification) else { return }
            windowVM.currentSession?.session.handleAction(action)
        }
        .onDisappear {
            windowVM.stopAllSessions()
        }
        // Browser sheets
        .sheet(isPresented: $vm.isShowingCloneDialog) {
            CloneDialogView()
                .environment(windowVM)
        }
        .sheet(isPresented: $vm.isShowingAddDialog) {
            AddRepositorySheet()
                .environment(windowVM)
        }
        .sheet(isPresented: $vm.isShowingCreateDialog) {
            CreateRepositorySheet()
                .environment(windowVM)
        }
    }

    // MARK: Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let ref = windowVM.openRepo {
            if let loaded = windowVM.currentSession {
                RepositoryContentRouter(session: loaded.session, repository: loaded.repository)
                    .repositoryToolbar(repository: loaded.repository, state: loaded.session.toolbarState)
                    .environment(loaded.session.gitUndoManager)
                    .focusedValue(\.gitUndoManager, loaded.session.gitUndoManager)
                    .id(ref.path)
            } else if let error = windowVM.sessionErrors[ref.path] {
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
        if !windowVM.isBrowsing {
            ToolbarItem(placement: .navigation) {
                Button {
                    windowVM.closeRepository()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back to Repositories")
            }
        }
    }
}

#Preview {
    RootWindowHost(manager: MockRepositoryManager())
}
