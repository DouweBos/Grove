// WorkingCopy/WorkingCopyDialogs.swift
// GroveUIKit
//
// The working copy's confirmations: discarding files, hunks or lines, renaming and moving to the Trash.

#if os(macOS)
import GroveKit
import SwiftUI

private struct WorkingCopyDialogs: ViewModifier {
    let viewModel: WorkingCopyViewModel
    @State private var suppressHunkWarning = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(discardTitle, isPresented: shown(viewModel.pendingDiscard != nil) { viewModel.cancelDiscard() },
                                titleVisibility: .visible, presenting: viewModel.pendingDiscard) { entries in
                Button("Discard", role: .destructive) { viewModel.act { await viewModel.discard(entries) } }
                Button("Cancel", role: .cancel) { viewModel.cancelDiscard() }
            } message: { entries in
                Text(entries.contains { $0.workdirStatus == .untracked }
                     ? "Uncommitted changes are lost and untracked files are deleted. This can't be undone."
                     : "This can't be undone.")
            }
            .confirmationDialog(viewModel.pendingHunkDiscard?.title ?? "", isPresented: shown(viewModel.pendingHunkDiscard != nil) {
                viewModel.cancelHunkDiscard()
            }, titleVisibility: .visible, presenting: viewModel.pendingHunkDiscard) { pending in
                Button("Discard", role: .destructive) {
                    viewModel.act { await viewModel.confirmHunkDiscard(pending, dontAskAgain: suppressHunkWarning) }
                }
                Button("Cancel", role: .cancel) { viewModel.cancelHunkDiscard() }
            } message: { _ in
                Text("The changes are removed from the working tree. This can't be undone.")
            }
            .dialogSuppressionToggle("Don\u{2019}t ask again", isSuppressed: $suppressHunkWarning)
            .confirmationDialog(trashTitle, isPresented: shown(trashEntries != nil) { viewModel.cancelFileAction() },
                                titleVisibility: .visible, presenting: trashEntries) { entries in
                Button("Move to Trash", role: .destructive) { viewModel.act { await viewModel.moveToTrash(entries) } }
                Button("Cancel", role: .cancel) { viewModel.cancelFileAction() }
            } message: { entries in
                Text("You can restore \(entries.count == 1 ? "it" : "them") from the Trash in Finder.")
            }
            .sheet(item: renameEntry) { entry in
                RenameFileSheet(entry: entry,
                                onRename: { newPath in viewModel.act { await viewModel.rename(entry, to: newPath) } },
                                onCancel: { viewModel.cancelFileAction() })
            }
    }

    private func shown(_ isShown: Bool, dismiss: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { isShown }, set: { if !$0 { dismiss() } })
    }

    private var discardTitle: String {
        guard let entries = viewModel.pendingDiscard, let entry = entries.first else { return "" }
        if entries.count > 1 { return "Discard all changes to \(entries.count) files?" }
        return entry.workdirStatus == .untracked
            ? "Delete untracked file \u{201C}\(entry.fileName)\u{201D}?"
            : "Discard all changes to \u{201C}\(entry.fileName)\u{201D}?"
    }

    private var trashEntries: [StatusEntry]? {
        if case .delete(let entries) = viewModel.pendingFileAction { return entries }
        return nil
    }

    private var trashTitle: String {
        guard let entries = trashEntries else { return "" }
        return entries.count == 1 ? "Move \u{201C}\(entries[0].fileName)\u{201D} to the Trash?" : "Move \(entries.count) files to the Trash?"
    }

    private var renameEntry: Binding<StatusEntry?> {
        Binding(get: {
            if case .rename(let entry) = viewModel.pendingFileAction { return entry }
            return nil
        }, set: { if $0 == nil { viewModel.cancelFileAction() } })
    }
}

extension View {
    /// The confirmations the working copy's discards, renames and Trash ask for, wherever its files are shown.
    public func gitWorkingCopyDialogs(_ viewModel: WorkingCopyViewModel) -> some View {
        modifier(WorkingCopyDialogs(viewModel: viewModel))
    }
}
#endif
