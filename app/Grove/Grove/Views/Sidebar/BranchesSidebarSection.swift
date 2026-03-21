// Views/Sidebar/BranchesSidebarSection.swift
// Grove

import SwiftUI

/// The BRANCHES section of the sidebar.
///
/// Renders flat branches directly and branches with "/" in their names
/// under collapsible `DisclosureGroup` sub-sections.
///
/// Branch rows are draggable (via `.draggable(branch.name)`). The consumer
/// (``RepositorySidebar``) adds the corresponding `.dropDestination` modifiers
/// to navigation items such as Working Copy.
///
/// The BRANCHES section header is itself a drop target: dropping a branch name
/// or commit SHA onto it opens the Create Branch sheet pre-filled with the
/// dropped ref as the "from" source.
struct BranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    // MARK: - Create-Branch-from-Drop State

    /// Whether the Create Branch sheet is currently presented.
    @State private var isShowingCreateBranchSheet = false
    /// The ref (branch name or commit SHA) that was dropped onto the BRANCHES
    /// header, used to pre-fill the starting point in the Create Branch sheet.
    @State private var createBranchFromRef: String?

    // MARK: Body

    var body: some View {
        Section(header: branchesHeader) {
            // Pinned branches at the top, separated by a divider.
            if !viewModel.pinnedBranches.isEmpty {
                ForEach(viewModel.pinnedBranches) { branch in
                    branchRow(branch, isPinned: true)
                }
                Divider()
                    .padding(.vertical, 2)
            }

            ForEach(viewModel.localBranchGroups, id: \.prefix) { group in
                if let prefix = group.prefix {
                    DisclosureGroup {
                        ForEach(group.branches) { branch in
                            branchRow(
                                branch,
                                isPinned: viewModel.pinnedBranchNames.contains(branch.name)
                            )
                        }
                    } label: {
                        Label(prefix, systemImage: "folder")
                            .font(.subheadline)
                    }
                } else {
                    ForEach(group.branches) { branch in
                        branchRow(
                            branch,
                            isPinned: viewModel.pinnedBranchNames.contains(branch.name)
                        )
                    }
                }
            }
        }
        // Present CreateBranchDialogView when a ref is dropped onto the header.
        .sheet(isPresented: $isShowingCreateBranchSheet) {
            CreateBranchDialogView(
                repository: viewModel.repository,
                localBranches: viewModel.localBranches,
                fromRef: createBranchFromRef
            ) { _ in
                Task { await viewModel.refresh() }
            }
        }
    }

    // MARK: - Branches Header

    /// The section header — doubles as a drop target for creating branches.
    private var branchesHeader: some View {
        SidebarSectionHeader(title: "Branches")
            // Drop target: a branch name or commit SHA dropped onto the BRANCHES
            // header opens the Create Branch sheet pre-filled with that ref.
            .dropDestination(for: String.self) { items, _ in
                guard let ref = items.first, !ref.isEmpty else { return false }
                createBranchFromRef = ref
                isShowingCreateBranchSheet = true
                return true
            }
    }

    // MARK: Branch Row

    @ViewBuilder
    private func branchRow(_ branch: BranchInfo, isPinned: Bool) -> some View {
        SidebarBranchRow(branch: branch, isPinned: isPinned)
            .tag(SidebarItem.branch(branch))
            // Make each branch draggable — the branch name is the transfer payload.
            .draggable(branch.name)
            .contextMenu {
                Button("Checkout \"\(branch.name)\"") {
                    Task { await viewModel.checkout(branch: branch) }
                }
                Divider()
                Button("Create Branch from \"\(branch.name)\"...") { }
                Button("Merge \"\(branch.name)\" into HEAD") {
                    Task { await viewModel.merge(branch: branch) }
                }
                Button("Rebase HEAD onto \"\(branch.name)\"") {
                    Task { await viewModel.rebase(onto: branch) }
                }
                Divider()
                Button("Rename \"\(branch.name)\"...") { }
                Button(isPinned ? "Unpin \"\(branch.name)\"" : "Pin \"\(branch.name)\"") {
                    viewModel.togglePin(branch: branch)
                }
                Divider()
                Button("Delete \"\(branch.name)\"...", role: .destructive) {
                    Task { await viewModel.deleteBranch(branch) }
                }
            }
    }
}

// MARK: - Preview

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.localBranches = MockData.branches.filter(\.isLocal)

    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        BranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 300)
}
