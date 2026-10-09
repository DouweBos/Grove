// Views/Sidebar/RemotesSidebarSection.swift
// Grove

import GroveKit
import SwiftUI

/// Remote-tracking branches grouped by remote, then in "prefix/" folders as local branches are. Without remotes it offers to add one, once refs have loaded.
struct RemotesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var isExpanded = true
    @State private var createFromRef: CreateBranchRequest?
    @State private var branchToDelete: BranchInfo?
    @State private var remoteToRemove: RemoteInfo?

    var body: some View {
        if !viewModel.remotes.isEmpty || viewModel.refs.hasLoaded {
            Section(isExpanded: $isExpanded) {
                if viewModel.remotes.isEmpty {
                    Button { viewModel.requestAddRemote() } label: {
                        SidebarRow(title: "Add Remote\u{2026}", symbol: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Connect this repository to a copy on GitHub or another server")
                }
                ForEach(viewModel.remotes) { remote in
                    let groups = viewModel.remoteBranchGroups(of: remote)
                    DisclosureGroup {
                        ForEach(groups, id: \.prefix) { group in
                            if let prefix = group.prefix {
                                BranchFolder(prefix: prefix, branches: group.branches) { remoteBranchRow($0) }
                            } else {
                                ForEach(group.branches) { remoteBranchRow($0) }
                            }
                        }
                    } label: {
                        SidebarRow(title: remote.name, symbol: "cloud", tint: Theme.info) {
                            Text("\(groups.reduce(0) { $0 + $1.branches.count })").font(.system(size: 11, design: .monospaced))
                        }
                        .help(remote.url + "\nDrop a local branch here to push it")
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first else { return false }
                            return viewModel.handleDrop(payload, onRemote: remote)
                        }
                        .contextMenu { remoteMenu(remote) }
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Remotes", count: viewModel.remotes.count)
                    .contextMenu {
                        Button("Add Remote\u{2026}", systemImage: "plus") { viewModel.requestAddRemote() }
                    }
            }
            .confirmationDialog(
                "Remove remote \u{201C}\(remoteToRemove?.name ?? "")\u{201D}?",
                isPresented: Binding(get: { remoteToRemove != nil }, set: { if !$0 { remoteToRemove = nil } }),
                presenting: remoteToRemove
            ) { remote in
                Button("Remove Remote", role: .destructive) { Task { await viewModel.actions.removeRemote(remote) } }
            } message: { remote in
                Text("Grove forgets \(remote.url) and its remote branches. Nothing on the server changes.")
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
                    Task { await viewModel.actions.deleteRemoteBranch(branch) }
                }
            } message: { _ in
                Text("The branch is removed from the server for everyone. This can't be undone from Grove.")
            }
        }
    }

    @ViewBuilder
    private func remoteMenu(_ remote: RemoteInfo) -> some View {
        Button("Copy URL", systemImage: "doc.on.doc") {
            GroveClipboard.copy(remote.url)
        }
        Divider()
        Button("Add Remote\u{2026}", systemImage: "plus") { viewModel.requestAddRemote() }
        Button("Remove Remote\u{2026}", systemImage: "trash", role: .destructive) { remoteToRemove = remote }
    }

    private func remoteBranchRow(_ branch: BranchInfo) -> some View {
        let shortName = RefActionsViewModel.shortName(of: branch)
        let hasLocal = viewModel.localBranches.contains { $0.name == shortName }
        let pullRequest = viewModel.refs.pullRequest(for: branch)
        let ciStatus = viewModel.refs.ciStatus(for: branch)
        return SidebarRow(title: shortName, symbol: "arrow.triangle.branch", tint: Theme.info, detail: pullRequest?.label,
                          detailSymbol: pullRequest?.detailSymbol, detailTint: Theme.renamed, isDimmed: pullRequest?.isMerged == true) {
            if let ciStatus { BranchCIStatusIcon(status: ciStatus) }
        }
            .help(([branch.name] + [pullRequest?.tooltip, ciStatus?.tooltip].compactMap { $0 }).joined(separator: "\n"))
            .tag(SidebarItem.remoteBranch(branch))
            .draggable(branch.name)
            .contextMenu {
                Button(hasLocal ? "Check Out \u{201C}\(shortName)\u{201D}" : "Check Out as Tracking Branch",
                       systemImage: "arrow.uturn.backward") {
                    Task { await viewModel.actions.checkout(remoteBranch: branch) }
                }
                Button("New Branch from \u{201C}\(branch.name)\u{201D}…", systemImage: "arrow.triangle.branch") {
                    createFromRef = CreateBranchRequest(ref: branch.name)
                }
                Button("Copy Name", systemImage: "doc.on.doc") {
                    GroveClipboard.copy(branch.name)
                }
                if let pullRequest { BranchPullRequestButton(pullRequest: pullRequest) }
                Button("Reveal in History", systemImage: "clock.arrow.circlepath") {
                    viewModel.revealInHistory(.remoteBranch(branch))
                }
                ExportFilesButton(ref: branch.name)
                if pullRequest == nil {
                    Button("Create Pull Request\u{2026}", systemImage: "arrow.triangle.pull") { viewModel.createPullRequest(for: branch) }
                }
                Button("Show Runs for Branch", systemImage: "play.circle") { viewModel.showRuns(for: branch) }
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
