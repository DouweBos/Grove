// Views/Toolbar/RepositoryMoreMenu.swift
// Grove
//
// The toolbar's More menu: secondary tabs, stash, new branch or tag, and git-flow.

import GroveKit
import SwiftUI

struct RepositoryMoreMenu: View {
    let toolbarState: RepositoryToolbarState
    let onNavigate: (SidebarItem) -> Void

    private var gitFlow: GitFlowViewModel { toolbarState.gitFlow }

    var body: some View {
        Menu {
            ForEach(RepositoryTab.secondary, id: \.self) { tab in
                Button { onNavigate(tab.item) } label: { Label(tab.title, systemImage: tab.symbol) }
            }
            Divider()
            Button { toolbarState.present(.stash) } label: { Label("Stash Changes…", systemImage: "tray.and.arrow.down") }
            Divider()
            Button { toolbarState.present(.branch) } label: { Label("New Branch…", systemImage: "arrow.triangle.branch") }
            Button { toolbarState.present(.tag) } label: { Label("New Tag…", systemImage: "tag") }
            Button { toolbarState.onAddSubmodule?() } label: { Label("Add Submodule…", systemImage: "shippingbox") }
            Button { toolbarState.onAddRemote?() } label: { Label("Add Remote…", systemImage: "cloud") }
            Divider()
            gitFlowMenu
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("More actions")
    }

    @ViewBuilder
    private var gitFlowMenu: some View {
        Menu {
            if gitFlow.isInitialized {
                ForEach(GitFlowKind.allCases) { kind in
                    Button { gitFlow.present(.start(kind)) } label: { Label("Start \(kind.title)…", systemImage: kind.symbol) }
                }
                Divider()
                if let current = gitFlow.currentFlowBranch {
                    Button("Finish \(current.kind.title) \u{201C}\(current.name)\u{201D}…") {
                        gitFlow.present(.finish(current.kind, name: current.name))
                    }
                }
                ForEach(GitFlowKind.allCases) { kind in
                    Button("Finish \(kind.title)…") { gitFlow.present(.finish(kind, name: nil)) }
                        .disabled(gitFlow.branchNames(of: kind).isEmpty)
                }
                Divider()
                Button("Git Flow Settings…") { gitFlow.present(.initialize) }
            } else {
                Button("Initialize Git Flow…") { gitFlow.present(.initialize) }
            }
        } label: {
            Label("Git Flow", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }
}

/// The sheet for whichever git-flow action is up.
struct GitFlowSheetView: View {
    let viewModel: GitFlowViewModel
    let sheet: GitFlowSheet

    var body: some View {
        switch sheet {
        case .initialize: GitFlowInitSheet(viewModel: viewModel)
        case .start(let kind): GitFlowStartSheet(viewModel: viewModel, kind: kind)
        case .finish(let kind, let name): GitFlowFinishSheet(viewModel: viewModel, kind: kind, name: name)
        }
    }
}

#Preview {
    let repo = MockGitRepository()
    let refs = RepositoryRefs(repository: repo)
    let state = RepositoryToolbarState(refs: refs, gitFlow: GitFlowViewModel(repository: repo, refs: refs),
                                       svn: SVNViewModel(repository: repo))
    return RepositoryMoreMenu(toolbarState: state) { _ in }
        .padding()
}
