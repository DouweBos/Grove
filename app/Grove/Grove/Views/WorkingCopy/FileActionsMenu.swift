// Views/WorkingCopy/FileActionsMenu.swift
// Grove
//
// Ignore, Stop Tracking, Rename and Delete items of the Changes context menu,
// plus the rename sheet and Trash confirmation they open.

import SwiftUI

struct FileActionsMenu: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    let entries: [StatusEntry]

    private var untracked: [StatusEntry] { entries.filter { $0.workdirStatus == .untracked } }
    private var tracked: [StatusEntry] { viewModel.trackedEntries(entries) }
    private var existing: [StatusEntry] { viewModel.existingEntries(entries) }

    var body: some View {
        if !untracked.isEmpty {
            Menu(untracked.count > 1 ? "Ignore \(untracked.count) Files" : "Ignore") {
                ignoreItems(localOnly: false)
                Divider()
                Menu("Local Only") { ignoreItems(localOnly: true) }
            }
        }
        if !tracked.isEmpty {
            Button(tracked.count > 1 ? "Stop Tracking \(tracked.count) Files" : "Stop Tracking") {
                Task { await viewModel.stopTracking(tracked) }
            }
        }
        if entries.count == 1, let entry = existing.first {
            Button("Rename\u{2026}") { viewModel.requestRename(entry) }
        }
        if !existing.isEmpty {
            Button(existing.count > 1 ? "Move \(existing.count) Files to Trash\u{2026}" : "Move to Trash\u{2026}") {
                viewModel.requestDelete(existing)
            }
        }
    }

    @ViewBuilder
    private func ignoreItems(localOnly: Bool) -> some View {
        ForEach(viewModel.ignoreTargets(for: untracked), id: \.self) { target in
            Button(title(for: target)) { Task { await viewModel.ignore(target, of: untracked, localOnly: localOnly) } }
        }
    }

    private func title(for target: IgnoreTarget) -> String {
        switch target {
        case .files: untracked.count == 1 ? "Ignore \u{201C}\(untracked[0].fileName)\u{201D}" : "Ignore These Files"
        case .fileExtension(let ext): "Ignore All \u{201C}*.\(ext)\u{201D} Files"
        case .folder(let folder): "Ignore Folder \u{201C}\(folder)\u{201D}"
        }
    }
}

// MARK: - Dialogs

/// Presents the rename sheet and the Trash confirmation for ``PendingFileAction``.
struct FileActionDialogs: ViewModifier {
    let viewModel: WorkingCopyViewModel

    func body(content: Content) -> some View {
        content
            .sheet(item: renameBinding) { entry in
                RenameFileSheet(entry: entry,
                                onRename: { newPath in Task { await viewModel.rename(entry, to: newPath) } },
                                onCancel: { viewModel.cancelFileAction() })
            }
            .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: deleteEntries) { entries in
                Button("Move to Trash", role: .destructive) { Task { await viewModel.moveToTrash(entries) } }
                Button("Cancel", role: .cancel) { viewModel.cancelFileAction() }
            } message: { entries in
                Text("You can restore \(entries.count == 1 ? "it" : "them") from the Trash in Finder.")
            }
    }

    private var deleteEntries: [StatusEntry]? {
        if case .delete(let entries) = viewModel.pendingFileAction { return entries }
        return nil
    }

    private var deleteTitle: String {
        guard let entries = deleteEntries else { return "" }
        return entries.count == 1 ? "Move \u{201C}\(entries[0].fileName)\u{201D} to the Trash?" : "Move \(entries.count) files to the Trash?"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteEntries != nil }, set: { if !$0 { viewModel.cancelFileAction() } })
    }

    private var renameBinding: Binding<StatusEntry?> {
        Binding(get: {
            if case .rename(let entry) = viewModel.pendingFileAction { return entry }
            return nil
        }, set: { if $0 == nil { viewModel.cancelFileAction() } })
    }
}

private struct RenameFileSheet: View {
    let entry: StatusEntry
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var newPath: String

    init(entry: StatusEntry, onRename: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.onRename = onRename
        self.onCancel = onCancel
        _newPath = State(initialValue: entry.path)
    }

    private var trimmed: String { newPath.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DialogSheet(
            title: "Rename \(entry.fileName)",
            message: entry.workdirStatus == .untracked
                ? "Include folders in the path to move the file."
                : "Tracked files are renamed with git mv, so the rename is staged.",
            symbol: "pencil",
            width: 460,
            primaryTitle: "Rename",
            isPrimaryDisabled: trimmed.isEmpty || trimmed == entry.path || trimmed.hasSuffix("/"),
            onCancel: onCancel,
            onPrimary: { onRename(trimmed) }
        ) {
            DialogCard {
                DialogField("New Path") {
                    TextField("Path", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
            }
        }
    }
}

#Preview("Rename") {
    RenameFileSheet(entry: MockData.statusEntries[0], onRename: { _ in }, onCancel: {})
}
