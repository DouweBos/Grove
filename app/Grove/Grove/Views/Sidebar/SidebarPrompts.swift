// Views/Sidebar/SidebarPrompts.swift
// Grove

import GroveKit
import SwiftUI

/// Presents the sidebar's `SidebarSheet` and `SidebarConfirmation`; attach it outside the List.
private struct SidebarPrompts: ViewModifier {
    @Bindable var viewModel: SidebarViewModel

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { viewModel.sheet }, set: { if $0 == nil { viewModel.dismissSheet() } })) { sheet in
                switch sheet {
                case .createBranch(let ref):
                    CreateBranchDialogView(repository: viewModel.repository, localBranches: viewModel.localBranches, fromRef: ref) { _ in
                        Task { await viewModel.didChangeRepository() }
                    }
                case .renameBranch(let branch):
                    RenameBranchDialogView(branch: branch) { try await viewModel.actions.renameBranch(branch, to: $0) }
                case .deleteBranch(let branch):
                    DeleteBranchDialogView(viewModel: viewModel, branch: branch)
                case .trackRemoteBranch(let branch):
                    TrackRemoteBranchDialogView(viewModel: viewModel, branch: branch)
                }
            }
            .confirmationDialog(
                viewModel.confirmation.map(Self.title) ?? "",
                isPresented: Binding(get: { viewModel.confirmation != nil }, set: { if !$0 { viewModel.dismissConfirmation() } }),
                presenting: viewModel.confirmation
            ) { confirmation in
                Button(Self.action(confirmation), role: .destructive) {
                    Task { await viewModel.confirm(confirmation) }
                }
            } message: { confirmation in
                Text(Self.message(confirmation))
            }
    }

    private static func title(_ confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .removeRemote(let remote): "Remove remote \u{201C}\(remote.name)\u{201D}?"
        case .deleteRemoteBranch(let branch): "Delete \u{201C}\(branch.name)\u{201D} on the remote?"
        case .deleteTag(let tag): "Delete the tag \u{201C}\(tag.name)\u{201D}?"
        case .removeSubmodule(let submodule): "Remove submodule \u{201C}\(submodule.displayName)\u{201D}?"
        }
    }

    private static func action(_ confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .removeRemote: "Remove Remote"
        case .deleteRemoteBranch: "Delete on Remote"
        case .deleteTag: "Delete Tag"
        case .removeSubmodule: "Remove Submodule"
        }
    }

    private static func message(_ confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .removeRemote(let remote):
            "Grove forgets \(remote.url) and its remote branches. Nothing on the server changes."
        case .deleteRemoteBranch:
            "The branch is removed from the server for everyone. This can't be undone from Grove."
        case .deleteTag:
            "Only the local tag is deleted; a pushed copy stays on the remote."
        case .removeSubmodule(let submodule):
            "Deletes \(submodule.path) and its clone, and stages the removal from .gitmodules. Uncommitted work in it is lost."
        }
    }
}

extension View {
    func sidebarPrompts(_ viewModel: SidebarViewModel) -> some View {
        modifier(SidebarPrompts(viewModel: viewModel))
    }
}
