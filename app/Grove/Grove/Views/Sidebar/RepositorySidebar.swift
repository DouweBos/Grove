// Views/Sidebar/RepositorySidebar.swift
// Grove

import SwiftUI

/// The full in-repository sidebar.
///
/// Top section: navigation items (Working Copy, History, Stashes, Pull Requests,
/// Branches Review, Settings). Bottom sections: BRANCHES, REMOTES, TAGS.
struct RepositorySidebar: View {

    @Environment(SidebarViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selection) {
            // MARK: Navigation Items

            Section {
                SidebarNavigationItem(
                    item: .workingCopy,
                    icon: "tray",
                    label: "Working Copy",
                    badge: viewModel.workingCopyBadgeCount
                )
                SidebarNavigationItem(
                    item: .history,
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    label: "History"
                )
                SidebarNavigationItem(
                    item: .stashes,
                    icon: "tray.2",
                    label: "Stashes"
                )
                SidebarNavigationItem(
                    item: .pullRequests,
                    icon: "arrow.triangle.pull",
                    label: "Pull Requests"
                )
                SidebarNavigationItem(
                    item: .branchesReview,
                    icon: "arrow.triangle.branch",
                    label: "Branch Review"
                )
                SidebarNavigationItem(
                    item: .settings,
                    icon: "gearshape",
                    label: "Settings"
                )
                .foregroundStyle(.secondary)
            }

            // MARK: Branches

            BranchesSidebarSection()

            // MARK: Remotes

            RemotesSidebarSection()

            // MARK: Tags

            TagsSidebarSection()
        }
        .listStyle(.sidebar)
        .task {
            await viewModel.refresh()
        }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    return NavigationSplitView {
        RepositorySidebar()
            .environment(vm)
    } detail: {
        Text("Detail")
    }
    .frame(width: 700, height: 500)
}
