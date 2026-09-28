// Views/Sidebar/RemotesSidebarSection.swift
// Grove

import SwiftUI

/// Remote-tracking branches grouped by remote. Hidden when the repository has no remotes.
struct RemotesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var isExpanded = true
    @State private var createFromRef: CreateBranchRequest?
    @State private var branchToDelete: BranchInfo?

    var body: some View {
        if !viewModel.remotes.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(viewModel.remotes) { remote in
                    let branches = viewModel.remoteBranches.filter { $0.remoteName == remote.name && !$0.name.hasSuffix("/HEAD") }
                    DisclosureGroup {
                        ForEach(branches) { remoteBranchRow($0) }
                    } label: {
                        SidebarRow(title: remote.name, symbol: "cloud", tint: Theme.info) {
                            Text("\(branches.count)").font(.system(size: 11, design: .monospaced))
                        }
                        .help(remote.url)
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Remotes", count: viewModel.remotes.count)
            }
            .sheet(item: $createFromRef) { request in
                CreateBranchDialogView(
                    repository: viewModel.repository,
                    localBranches: viewModel.localBranches,
                    fromRef: request.ref
                ) { _ in
                    Task { await viewModel.didChangeRepository() }
                }
            }
            .confirmationDialog(
                "Delete \u{201C}\(branchToDelete?.name ?? "")\u{201D} on the remote?",
                isPresented: Binding(get: { branchToDelete != nil }, set: { if !$0 { branchToDelete = nil } }),
                presenting: branchToDelete
            ) { branch in
                Button("Delete on Remote", role: .destructive) {
                    Task { await viewModel.deleteRemoteBranch(branch) }
                }
            } message: { _ in
                Text("The branch is removed from the server for everyone. This can't be undone from Grove.")
            }
        }
    }

    private func remoteBranchRow(_ branch: BranchInfo) -> some View {
        let shortName = SidebarViewModel.shortName(of: branch)
        let hasLocal = viewModel.localBranches.contains { $0.name == shortName }
        return SidebarRow(title: shortName, symbol: "arrow.triangle.branch", tint: Theme.info)
            .tag(SidebarItem.remoteBranch(branch))
            .draggable(branch.name)
            .contextMenu {
                Button(hasLocal ? "Check Out \u{201C}\(shortName)\u{201D}" : "Check Out as Tracking Branch",
                       systemImage: "arrow.uturn.backward") {
                    Task { await viewModel.checkout(remoteBranch: branch) }
                }
                Button("New Branch from \u{201C}\(branch.name)\u{201D}…", systemImage: "arrow.triangle.branch") {
                    createFromRef = CreateBranchRequest(ref: branch.name)
                }
                Button("Copy Name", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branch.name, forType: .string)
                }
                Divider()
                Button("Delete on Remote…", systemImage: "trash", role: .destructive) {
                    branchToDelete = branch
                }
            }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes)
    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        RemotesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 240, height: 200)
}
