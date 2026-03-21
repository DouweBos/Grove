// Views/Sidebar/ArchivedBranchesSidebarSection.swift
// Grove

import SwiftUI

/// The ARCHIVED BRANCHES section of the sidebar.
///
/// Displays local branches that are fully merged into HEAD (ahead == 0) and therefore
/// considered stale or no longer actively developed. The section is collapsible so it
/// stays out of the way during normal work.
struct ArchivedBranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var isExpanded = false

    var body: some View {
        if !viewModel.archivedBranches.isEmpty {
            Section(header: SidebarSectionHeader(title: "Archived Branches")) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(viewModel.archivedBranches) { branch in
                        archivedBranchRow(branch)
                    }
                } label: {
                    Label {
                        HStack {
                            Text("\(viewModel.archivedBranches.count) merged branches")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func archivedBranchRow(_ branch: BranchInfo) -> some View {
        SidebarBranchRow(branch: branch)
            .tag(SidebarItem.branch(branch))
            .contextMenu {
                Button("Checkout \"\(branch.name)\"") {
                    Task { await viewModel.checkout(branch: branch) }
                }
                Divider()
                Button("Unarchive \"\(branch.name)\"") {
                    // Unarchiving means creating a new commit on this branch,
                    // which moves ahead > 0 and removes it from archived.
                    // For now this is a placeholder — the user should push or
                    // create a commit to bring it out of archived state.
                }
                Button("Delete \"\(branch.name)\"...", role: .destructive) {
                    Task { await viewModel.deleteBranch(branch) }
                }
            }
    }
}

// MARK: - Preview

#Preview("With archived branches") {
    let vm = SidebarViewModel(repository: MockGitRepository())
    // Branches with ahead == 0 and isHEAD == false are treated as archived.
    vm.localBranches = MockData.branches.filter(\.isLocal)

    return List(selection: Binding<SidebarItem?>.constant(nil)) {
        ArchivedBranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 160)
}

#Preview("No archived branches") {
    let vm = SidebarViewModel(repository: MockGitRepository())
    // Give every branch at least one ahead commit so nothing is archived.
    vm.localBranches = MockData.branches.filter(\.isLocal).map { branch in
        BranchInfo(
            id: branch.id,
            name: branch.name,
            isLocal: branch.isLocal,
            isRemote: branch.isRemote,
            isHEAD: branch.isHEAD,
            targetSHA: branch.targetSHA,
            remoteName: branch.remoteName,
            upstream: branch.upstream,
            ahead: branch.isHEAD ? branch.ahead : max(branch.ahead, 1),
            behind: branch.behind
        )
    }

    return List(selection: Binding<SidebarItem?>.constant(nil)) {
        ArchivedBranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 60)
}
