// Views/Sidebar/BranchActionSheets.swift
// Grove
//
// The new, rename and delete sheets a branch row's context menu opens, shared by Branches and Stacks.

import SwiftUI

/// Which branch sheet is up; one per section, so each section's rows present their own.
struct BranchSheetState {
    var createFromRef: CreateBranchRequest?
    var branchToRename: BranchInfo?
    var branchToDelete: BranchInfo?
    var branchToTrack: BranchInfo?
}

private struct BranchActionSheets: ViewModifier {
    @Environment(SidebarViewModel.self) private var viewModel
    @Binding var state: BranchSheetState

    func body(content: Content) -> some View {
        content
            .sheet(item: $state.createFromRef) { request in
                CreateBranchDialogView(
                    repository: viewModel.repository,
                    localBranches: viewModel.localBranches,
                    fromRef: request.ref
                ) { _ in
                    Task { await viewModel.didChangeRepository() }
                }
            }
            .sheet(item: $state.branchToRename) { branch in
                RenameBranchDialogView(repository: viewModel.repository, branch: branch) {
                    Task { await viewModel.didChangeRepository() }
                }
            }
            .sheet(item: $state.branchToDelete) { branch in
                DeleteBranchDialogView(viewModel: viewModel, branch: branch)
            }
            .sheet(item: $state.branchToTrack) { branch in
                TrackRemoteBranchDialogView(viewModel: viewModel, branch: branch)
            }
    }
}

extension View {
    func branchActionSheets(_ state: Binding<BranchSheetState>) -> some View {
        modifier(BranchActionSheets(state: state))
    }
}
