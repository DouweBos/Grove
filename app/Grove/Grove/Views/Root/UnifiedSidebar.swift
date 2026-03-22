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
    }
}
