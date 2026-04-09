// Views/Sidebar/RemotesSidebarSection.swift
// Grove

import SwiftUI

/// The REMOTES section of the sidebar.
///
/// Groups remote-tracking branches by their remote name (e.g. "origin", "upstream").
struct RemotesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    // MARK: - Sheet / Alert State

    @State private var isShowingCreateBranch = false
    @State private var createBranchFromRef: String?

    @State private var isShowingDeleteAlert = false
    @State private var branchToDelete: BranchInfo?

    var body: some View {
        Section(header: SidebarSectionHeader(title: "Remotes")) {
            ForEach(viewModel.remotes) { remote in
                DisclosureGroup {
                    let branches = viewModel.remoteBranches.filter {
                        $0.remoteName == remote.name
                    }
                    ForEach(branches) { branch in
                        remoteBranchRow(branch)
                    }
                } label: {
                    Label(remote.name, systemImage: "network")
                        .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateBranch) {
            CreateBranchDialogView(
                repository: viewModel.repository,
                localBranches: viewModel.localBranches,
                fromRef: createBranchFromRef
            ) { _ in
                Task { await viewModel.refresh() }
            }
        }
        .alert(
            "Delete Remote Branch",
            isPresented: $isShowingDeleteAlert,
            presenting: branchToDelete
        ) { branch in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteRemoteBranch(branch) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { branch in
            let displayName = Self.displayName(for: branch)
            Text("Delete \"\(displayName)\" on the remote? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func remoteBranchRow(_ branch: BranchInfo) -> some View {
        let displayName = Self.displayName(for: branch)

        Label(displayName, systemImage: "arrow.triangle.branch")
            .font(.subheadline)
            .lineLimit(1)
            .tag(SidebarItem.remoteBranch(branch))
            .contextMenu {
                Button("Checkout \"\(displayName)\"...") {
                    Task { await viewModel.checkout(branch: branch) }
                }
                Button("Create Local Branch from \"\(displayName)\"...") {
                    createBranchFromRef = branch.name
                    isShowingCreateBranch = true
                }
                Divider()
                Button("Delete \"\(displayName)\" on Remote...", role: .destructive) {
                    branchToDelete = branch
                    isShowingDeleteAlert = true
                }
            }
    }

    /// Strip "remoteName/" prefix for display.
    private static func displayName(for branch: BranchInfo) -> String {
        if let remote = branch.remoteName,
           branch.name.hasPrefix(remote + "/") {
            return String(branch.name.dropFirst(remote.count + 1))
        }
        return branch.name
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.remotes = MockData.remotes
    vm.remoteBranches = MockData.branches.filter(\.isRemote)

    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        RemotesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 200)
}
