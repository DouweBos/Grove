// Views/Sidebar/RepositorySidebar.swift
// Grove

import SwiftUI

/// In-repository sidebar: a summary of the repository, then its refs.
/// Top-level destinations (Changes, History, …) live in the toolbar pills.
struct RepositorySidebar: View {

    @Environment(SidebarViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selection) {
            Section {
                RepositorySummaryHeader()
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
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

// MARK: - RepositorySummaryHeader

/// Repository name and checked-out branch, like Charon's disk summary.
private struct RepositorySummaryHeader: View {
    @Environment(SidebarViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(viewModel.repository.path.lastPathComponent)
                .font(.pageTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(branchSummary)
                    .font(.monoCaption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var branchSummary: String {
        guard let head = viewModel.localBranches.first(where: \.isHEAD) else { return "Detached HEAD" }
        var parts = [head.name]
        if head.ahead > 0 { parts.append("↑\(head.ahead)") }
        if head.behind > 0 { parts.append("↓\(head.behind)") }
        return parts.joined(separator: " ")
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
