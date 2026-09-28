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

    // MARK: ViewModels

    @State private var windowVM: WindowViewModel

    // MARK: Split View

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var mouseMonitor: Any?

    // MARK: Init

    init(windowVM: WindowViewModel) {
        self._windowVM = State(initialValue: windowVM)
    }

    // MARK: Body

    var body: some View {
        @Bindable var vm = windowVM

        NavigationSplitView(columnVisibility: $columnVisibility) {
            UnifiedSidebar(session: windowVM.currentSession?.session, isCollapsed: columnVisibility == .detailOnly)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailContent
        }
        .navigationTitle(windowVM.openRepo?.displayName ?? "Grove")
        .toolbar(removing: .title)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            if columnVisibility == .detailOnly {
                RepositoryHomeButtons(placement: .navigation)
            }
            NavigationHistoryButtons()
        }
        // Mouse buttons 4 and 5 (back / forward) arrive as other-mouse clicks; SwiftUI has no handler for them.
        .onAppear {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [windowVM] event in
                switch event.buttonNumber {
                case 3: windowVM.goBack()
                case 4: windowVM.goForward()
                default: return event
                }
                return nil
            }
        }
        .onDisappear {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }
        .environment(windowVM)
        // Load session when openRepo changes
        .onChange(of: windowVM.openRepo) { _, ref in
            if let ref {
                windowVM.loadSessionIfNeeded(for: ref)
            }
        }
        // Repository actions → forward to active session
        .onReceive(
            NotificationCenter.default.publisher(for: GroveAction.notificationName)
        ) { notification in
            guard let action = GroveAction(notification: notification),
                  !windowVM.handleBrowserAction(action) else { return }
            windowVM.currentSession?.session.handleAction(action)
        }
        // Reopening the window resumes the repository it was showing.
        .onAppear {
            if let ref = windowVM.openRepo { windowVM.loadSessionIfNeeded(for: ref) }
        }
        .onDisappear {
            windowVM.pauseCurrentSession()
        }
        // `-GroveOpenRepository <path>` opens a repository on launch.
        .task {
            // `-GroveSidebar hidden` collapses the sidebar, for checking the collapsed toolbar.
            if UserDefaults.standard.string(forKey: "GroveSidebar") == "hidden" {
                try? await Task.sleep(for: .milliseconds(300))
                columnVisibility = .detailOnly
            }
            if UserDefaults.standard.string(forKey: "GroveOpenRepository") == nil,
               let raw = UserDefaults.standard.string(forKey: "GroveAction"), let action = GroveAction(rawValue: raw) {
                _ = windowVM.handleBrowserAction(action)
            }
            if let path = UserDefaults.standard.string(forKey: "GroveOpenRepository") {
                windowVM.openReference(RepositoryReference(path: path))
            }
        }
        // Browser sheets
        .sheet(isPresented: $vm.isShowingCloneDialog) {
            CloneDialogView(initialURL: windowVM.cloneURLPrefill)
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
        .sheet(item: $vm.groupEditor) { editor in
            GroupNameSheet(editor: editor)
                .environment(windowVM)
        }
        .alert(undoManager?.errorTitle ?? "Couldn't Undo", isPresented: undoErrorPresented) {
            Button("OK") { undoManager?.dismissError() }
        } message: {
            Text(undoManager?.errorMessage ?? "")
        }
    }

    // MARK: Undo Errors

    private var undoManager: GitUndoManager? { windowVM.currentSession?.session.gitUndoManager }

    private var undoErrorPresented: Binding<Bool> {
        Binding(get: { undoManager?.errorMessage != nil },
                set: { if !$0 { undoManager?.dismissError() } })
    }

    // MARK: Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let ref = windowVM.openRepo {
            if let loaded = windowVM.currentSession {
                RepositoryContentRouter(session: loaded.session, repository: loaded.repository)
                    .quickActions(session: loaded.session)
                    .repositoryToolbar(
                        repository: loaded.repository,
                        state: loaded.session.toolbarState,
                        sidebarVM: loaded.session.sidebarVM,
                        onComplete: { Task { await loaded.session.refreshAll() } }
                    )
                    .environment(loaded.session.gitUndoManager)
                    .onAppear { EditUndoState.shared.attach(loaded.session.gitUndoManager) }
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
        } else if windowVM.browserMode == .remote {
            RemoteRepositoriesContent()
                .onAppear { EditUndoState.shared.attach(nil) }
        } else {
            RepositoryBrowserContent()
                .onAppear { EditUndoState.shared.attach(nil) }
        }
    }
}

// MARK: - NavigationHistoryButtons

/// Back / forward through the window's history, as one tight group like the home buttons.
private struct NavigationHistoryButtons: ToolbarContent {
    @Environment(WindowViewModel.self) private var viewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 0) {
                button("chevron.left", help: "Back (\u{2318}[)", enabled: viewModel.canGoBack) { viewModel.goBack() }
                button("chevron.right", help: "Forward (\u{2318}])", enabled: viewModel.canGoForward) { viewModel.goForward() }
            }
        }
    }

    private func button(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.5))
        .disabled(!enabled)
        .help(help)
    }
}

#Preview {
    RootWindowHost(windowVM: WindowViewModel(manager: MockRepositoryManager()))
}
