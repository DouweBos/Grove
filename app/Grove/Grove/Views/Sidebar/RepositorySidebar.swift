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

            // MARK: Worktrees

            WorktreesSidebarSection()

            // MARK: Archived Branches

            ArchivedBranchesSidebarSection()

            // MARK: Remotes

            RemotesSidebarSection()

            // MARK: Tags

            TagsSidebarSection()

            // MARK: Submodules

            SubmodulesSidebarSection()
        }
        .listStyle(.sidebar)
        // Double-click / Return on a branch; a tap gesture on the row itself would eat the click that selects it.
        .contextMenu(forSelectionType: SidebarItem.self) { _ in
        } primaryAction: { items in
            guard case .branch(let branch) = items.first else { return }
            Task { await viewModel.activate(branch: branch) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = viewModel.errorMessage {
                Banner(symbol: "xmark.octagon", message: message, tone: .negative) { viewModel.dismissError() }
                    .padding(Theme.Spacing.sm)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

// MARK: - WorktreeSwitcher

/// Which worktree this window runs git in, with a menu to switch to another, like Charon's disk picker.
private struct WorktreeSwitcher: View {
    @Environment(SidebarViewModel.self) private var viewModel
    let isLinkedWorktree: Bool

    var body: some View {
        Menu {
            Section("Worktrees") {
                ForEach(viewModel.worktrees) { worktree in
                    Button { viewModel.switchTo(worktree) } label: {
                        Label(title(worktree), systemImage: viewModel.isCurrent(worktree) ? "checkmark" : "tree")
                    }
                    .disabled(worktree.isPrunable)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "tree")
                Text(isLinkedWorktree ? URL(fileURLWithPath: viewModel.repository.path.path).lastPathComponent : "Main worktree")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("Git commands run in \(abbreviatingHome(viewModel.repository.path.path)). Choose another worktree to switch.")
    }

    private func title(_ worktree: WorktreeInfo) -> String {
        let name = worktree.branch ?? worktree.folderName
        return worktree.isMain ? "\(name) (main)" : name
    }
}

// MARK: - RepositorySummaryHeader

/// Repository name, checked-out branch and its sync state, like Charon's disk summary.
private struct RepositorySummaryHeader: View {
    @Environment(SidebarViewModel.self) private var viewModel
    /// Main repository path when this window shows a linked worktree.
    @State private var mainRepositoryPath: String?

    private var head: BranchInfo? { viewModel.localBranches.first(where: \.isHEAD) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // A worktree's folder name is incidental; the repository it belongs to is what matters.
            Text(mainRepositoryPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? viewModel.repository.path.lastPathComponent)
                .font(.pageTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if viewModel.worktrees.count > 1 {
                WorktreeSwitcher(isLinkedWorktree: mainRepositoryPath != nil)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: head == nil ? "exclamationmark.triangle" : "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(head?.name ?? "Detached HEAD")
                    .font(.monoCaption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let upstream = head?.upstreamShortName {
                    Text("\u{2192} \(upstream)")
                        .font(.monoCaption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(Theme.textSecondary)
            badges
        }
        .padding(.vertical, Theme.Spacing.sm)
        .task(id: viewModel.repository.path) {
            mainRepositoryPath = WorktreeResolver.mainRepositoryPath(forWorktreeAt: viewModel.repository.path.path)
        }
    }

    @ViewBuilder
    private var badges: some View {
        let changes = viewModel.workingCopyBadgeCount
        let ahead = head?.ahead ?? 0
        let behind = head?.behind ?? 0
        // Without an upstream there's nothing to compare against, so "up to date" would be a guess.
        let unpublished = head != nil && head?.upstream == nil
        if changes > 0 || ahead > 0 || behind > 0 || unpublished {
            HStack(spacing: Theme.Spacing.xs) {
                if changes > 0 {
                    StatusBadge(title: "\(changes) changed", symbol: "pencil", tone: .caution)
                }
                if unpublished {
                    StatusBadge(title: "Not published", symbol: "icloud.slash", tone: .neutral)
                }
                if ahead > 0 {
                    StatusBadge(title: "\(ahead) to push", symbol: "arrow.up", tone: .neutral)
                }
                if behind > 0 {
                    StatusBadge(title: "\(behind) to pull", symbol: "arrow.down", tone: .caution)
                }
            }
        } else {
            StatusBadge(title: "Up to date", symbol: "checkmark.circle.fill", tone: .positive)
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
