// Views/Sidebar/BranchesSidebarSection.swift
// Grove

import SwiftUI

/// The BRANCHES section of the sidebar.
///
/// Renders flat branches directly and branches with "/" in their names
/// under collapsible `DisclosureGroup` sub-sections.
struct BranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    var body: some View {
        Section(header: SidebarSectionHeader(title: "Branches")) {
            ForEach(viewModel.localBranchGroups, id: \.prefix) { group in
                if let prefix = group.prefix {
                    DisclosureGroup {
                        ForEach(group.branches) { branch in
                            branchRow(branch)
                        }
                    } label: {
                        Label(prefix, systemImage: "folder")
                            .font(.subheadline)
                    }
                } else {
                    ForEach(group.branches) { branch in
                        branchRow(branch)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func branchRow(_ branch: BranchInfo) -> some View {
        SidebarBranchRow(branch: branch)
            .tag(SidebarItem.branch(branch))
            .contextMenu {
                Button("Checkout \"\(branch.name)\"") {
                    Task { await viewModel.checkout(branch: branch) }
                }
                Divider()
                Button("Create Branch from \"\(branch.name)\"...") { }
                Button("Merge \"\(branch.name)\" into HEAD") { }
                Button("Rebase HEAD onto \"\(branch.name)\"") { }
                Divider()
                Button("Rename \"\(branch.name)\"...") { }
                Button("Delete \"\(branch.name)\"...", role: .destructive) {
                    Task { await viewModel.deleteBranch(branch) }
                }
            }
    }
}

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
