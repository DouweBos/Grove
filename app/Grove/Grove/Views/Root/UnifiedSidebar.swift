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
    
    @Environment(WindowViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let session {
                RepositorySidebar()
                    .environment(session.sidebarVM)
                    .transition(.opacity)
            } else {
                RepositoryGroupsSidebar()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: session != nil)
        .frame(minWidth: 320)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.setSourceMode(.cloud)
                } label: {
                    Image(systemName: viewModel.sourceMode == .cloud ? "cloud.fill" : "cloud")
                }
                .help("Cloud Repositories")

                Button {
                    viewModel.setSourceMode(.local)
                } label: {
                    Image(systemName: viewModel.sourceMode == .local ? "externaldrive.fill" : "externaldrive")
                }
                .help("Local Repositories")
            }
        }
    }
}
