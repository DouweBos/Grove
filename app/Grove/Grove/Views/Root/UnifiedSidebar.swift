// Views/Root/UnifiedSidebar.swift
// Grove
//
// A single sidebar that transitions between the repository browser
// (bookmark groups) and in-repository navigation (branches, tags, etc.)
// based on whether a RepositorySession is active. Used inside the
// permanent NavigationSplitView in RootWindowHost so the split view
// shell is never destroyed, avoiding the jarring flash on navigation.

import SwiftUI

// MARK: - UnifiedSidebar

struct UnifiedSidebar: View {

    /// Active repository session, or `nil` when showing the browser.
    let session: RepositorySession?
    /// While collapsed the window's top bar shows the home buttons; SwiftUI would squeeze the sidebar's copy.
    var isCollapsed = false
    
    @Environment(WindowViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let session {
                RepositorySidebar()
                    .environment(session.sidebarVM)
                    .transition(.opacity)
            } else if viewModel.browserMode == .remote {
                RemoteRepositoriesSidebar()
                    .transition(.opacity)
            } else {
                RepositoryGroupsSidebar()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: session != nil)
        .toolbar {
            if !isCollapsed {
                RepositoryHomeButtons(placement: .primaryAction)
            }
            if session == nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add Existing Repository…", systemImage: "folder.badge.plus") { viewModel.showAddDialog() }
                        Button("Clone Repository…", systemImage: "square.and.arrow.down") { viewModel.showCloneDialog() }
                        Button("New Repository…", systemImage: "plus.square.on.square") { viewModel.showCreateDialog() }
                        Divider()
                        Button("New Group…", systemImage: "folder.badge.plus") { viewModel.showNewGroupDialog() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a repository")
                }
            }
        }
    }
}

// MARK: - RepositoryHomeButtons

/// Home buttons: both leave an open repository; the cloud lists hosted repositories, the disk local ones.
struct RepositoryHomeButtons: ToolbarContent {
    @Environment(WindowViewModel.self) private var viewModel
    let placement: ToolbarItemPlacement

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            Button { viewModel.showRemoteRepositories() } label: {
                Image(systemName: isShowing(.remote) ? "cloud.fill" : "cloud")
            }
            .help("Remote Repositories (\u{21E7}\u{2318}K)")
            Button { viewModel.showLocalRepositories() } label: {
                Image(systemName: isShowing(.local) ? "externaldrive.fill" : "externaldrive")
            }
            .help("Local Repositories (\u{21E7}\u{2318}L)")
        }
    }

    private func isShowing(_ mode: WindowViewModel.BrowserMode) -> Bool {
        viewModel.isBrowsing && viewModel.browserMode == mode
    }
}
