// Views/Sidebar/RemotesSidebarSection.swift
// Grove

import SwiftUI

/// The REMOTES section of the sidebar.
///
/// Groups remote-tracking branches by their remote name (e.g. "origin", "upstream").
struct RemotesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

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
    }

    @ViewBuilder
    private func remoteBranchRow(_ branch: BranchInfo) -> some View {
        // Strip "remoteName/" prefix for display
        let displayName: String = {
            if let remote = branch.remoteName,
               branch.name.hasPrefix(remote + "/") {
                return String(branch.name.dropFirst(remote.count + 1))
            }
            return branch.name
        }()

        Label(displayName, systemImage: "arrow.triangle.branch")
            .font(.subheadline)
            .lineLimit(1)
            .tag(SidebarItem.remoteBranch(branch))
            .contextMenu {
                Button("Checkout \"\(displayName)\"...") { }
                Button("Create Local Branch from \"\(displayName)\"...") { }
                Divider()
                Button("Delete \"\(displayName)\" on Remote...", role: .destructive) { }
            }
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
