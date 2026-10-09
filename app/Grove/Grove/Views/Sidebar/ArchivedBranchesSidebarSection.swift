// Views/Sidebar/ArchivedBranchesSidebarSection.swift
// Grove

import GroveKit
import SwiftUI

/// Branches the user archived to declutter the Branches list. Collapsed by default,
/// hidden when empty.
struct ArchivedBranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var isExpanded = false

    var body: some View {
        let branches = viewModel.archivedBranches
        if !branches.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(branches) { branch in
                    SidebarBranchRow(branch: branch, showsFullName: true)
                        .tag(SidebarItem.branch(branch))
                        .draggable(branch.name)
                        .contextMenu {
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { viewModel.unarchive(branch: branch) }
                            Button("Check Out \u{201C}\(branch.name)\u{201D}", systemImage: "arrow.uturn.backward") {
                                Task { await viewModel.actions.checkout(branch: branch) }
                            }
                            Divider()
                            Button("Delete…", systemImage: "trash", role: .destructive) { viewModel.present(.deleteBranch(branch)) }
                        }
                }
            } header: {
                SidebarSectionHeader(title: "Archived", count: branches.count)
            }
        }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(localBranches: MockData.branches.filter(\.isLocal))
    vm.archivedBranchNames = Set(vm.localBranches.dropFirst().map(\.name))
    return List(selection: Binding<SidebarItem?>.constant(nil)) {
        ArchivedBranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 240, height: 200)
}
