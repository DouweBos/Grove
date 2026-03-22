// Views/Sidebar/RepositorySidebar.swift
// Grove

import SwiftUI
import AppKit

/// The full in-repository sidebar.
///
/// Top section: navigation items (Working Copy, History, Stashes, Reflog, Blame,
/// Pull Requests, Branches Review, Settings).
/// Bottom sections: BRANCHES, ARCHIVED BRANCHES, REMOTES, TAGS, SUBMODULES, WORKTREES.
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
                // Drop target: Working Copy accepts three kinds of drag payloads.
                //
                //   • Branch name  → merge into HEAD (default) or rebase (Option key)
                //   • Commit SHA   → cherry-pick onto HEAD
                //   • "stash@{N}" → apply stash N without dropping it
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }

                    // Stash ref: "stash@{<index>}"
                    if payload.hasPrefix("stash@{"), payload.hasSuffix("}") {
                        let inner = payload.dropFirst("stash@{".count).dropLast()
                        if let index = Int(inner) {
                            Task { await viewModel.stashApply(index: index) }
                            return true
                        }
                    }

                    // Commit SHA: 40 hex chars (full SHA) or at least 7 hex chars (short SHA).
                    let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
                    let isHexString = payload.unicodeScalars.allSatisfy { hexChars.contains($0) }
                    if isHexString && payload.count >= 7 {
                        Task { await viewModel.cherryPick(sha: payload) }
                        return true
                    }

                    // Branch name → merge or rebase.
                    guard let branch = viewModel.localBranches.first(where: { $0.name == payload }) else { return false }
                    // When the Option key is held at drop time, rebase HEAD
                    // onto the dragged branch instead of merging.
                    let optionHeld = NSEvent.modifierFlags.contains(.option)
                    if optionHeld {
                        Task { await viewModel.rebase(onto: branch) }
                    } else {
                        Task { await viewModel.merge(branch: branch) }
                    }
                    return true
                }
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
                    item: .reflog,
                    icon: "clock.arrow.circlepath",
                    label: "Reflog"
                )
                SidebarNavigationItem(
                    item: .blame,
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Blame"
                )
                SidebarNavigationItem(
                    item: .pullRequests,
                    icon: "arrow.triangle.pull",
                    label: "Pull Requests"
                )
                SidebarNavigationItem(
                    item: .branchesReview,
                    icon: "arrow.triangle.branch",
                    label: "Branches Review"
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

            // MARK: Archived Branches

            ArchivedBranchesSidebarSection()

            // MARK: Remotes

            RemotesSidebarSection()

            // MARK: Tags

            TagsSidebarSection()

            // MARK: Submodules

            SubmodulesSidebarSection()

            // MARK: Worktrees

            WorktreesSidebarSection()
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
