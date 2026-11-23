// Dialogs/GitDialogView.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// One of the shared dialogs, for a sheet. It closes itself through `dismiss`, telling `onFinish` whether it ran.
public struct GitDialogView: View {
    @Environment(\.dismiss) private var dismiss
    private let dialog: GitDialog
    private let context: GitDialogContext
    private let onFinish: ((Bool) -> Void)?

    public init(_ dialog: GitDialog, context: GitDialogContext, onFinish: ((Bool) -> Void)? = nil) {
        self.dialog = dialog
        self.context = context
        self.onFinish = onFinish
    }

    public var body: some View {
        content.gitFeatures(context.features)
    }

    @ViewBuilder
    private var content: some View {
        switch dialog {
        case .fetch: FetchDialog(context: context, close: close)
        case .pull: PullDialog(context: context, close: close)
        case .push(let branch): PushDialog(name: branch, context: context, close: close)
        case .sync: SyncDialog(context: context, close: close)
        case .createBranch(let start): CreateBranchDialog(from: start, context: context, close: close)
        case .renameBranch(let name): RenameBranchDialog(branch: name, context: context, close: close)
        case .renameCurrentBranch: RenameBranchDialog(branch: nil, context: context, close: close)
        case .deleteBranch(let branch): DeleteBranchDialog(branch: branch, context: context, close: close)
        case .trackRemoteBranch(let branch): TrackDialog(branch: branch, context: context, close: close)
        case .merge: MergeDialog(context: context, close: close)
        case .rebase: RebaseDialog(context: context, close: close)
        case .stash(let paths): StashDialog(paths: paths, context: context, close: close)
        case .snapshot: SnapshotDialog(context: context, close: close)
        case .createTag(let target): TagDialog(target: target, context: context, close: close)
        case .addRemote: RemoteDialog(remote: nil, context: context, close: close)
        case .editRemote(let remote): RemoteDialog(remote: remote, context: context, close: close)
        case .branchFromStash(let index): StashBranchDialog(index: index, context: context, close: close)
        }
    }

    private func close(_ submitted: Bool) {
        onFinish?(submitted)
        dismiss()
    }
}
#endif
