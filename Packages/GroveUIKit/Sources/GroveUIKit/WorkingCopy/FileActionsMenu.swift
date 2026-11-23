// WorkingCopy/FileActionsMenu.swift
// GroveUIKit
//
// Ignore, Stop Tracking, Rename and Move to Trash in a Changes row's menu.

#if os(macOS)
import GroveKit
import SwiftUI

struct FileActionsMenu: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    let entries: [StatusEntry]

    private var untracked: [StatusEntry] { entries.filter { $0.workdirStatus == .untracked } }

    var body: some View {
        if !untracked.isEmpty {
            Menu(untracked.count > 1 ? "Ignore \(untracked.count) Files" : "Ignore") {
                ignoreItems(localOnly: false)
                Divider()
                Menu("Local Only") { ignoreItems(localOnly: true) }
            }
        }
        let tracked = viewModel.trackedEntries(entries)
        if !tracked.isEmpty {
            Button(tracked.count > 1 ? "Stop Tracking \(tracked.count) Files" : "Stop Tracking") {
                viewModel.act { await viewModel.stopTracking(tracked) }
            }
        }
        let existing = viewModel.existingEntries(entries)
        if entries.count == 1, let entry = existing.first {
            Button("Rename") { viewModel.requestRename(entry) }
        }
        if !existing.isEmpty {
            Button(existing.count > 1 ? "Move \(existing.count) Files to Trash" : "Move to Trash") {
                viewModel.requestDelete(existing)
            }
            .requires(.trash)
        }
    }

    @ViewBuilder
    private func ignoreItems(localOnly: Bool) -> some View {
        ForEach(viewModel.ignoreTargets(for: untracked), id: \.self) { target in
            Button(title(for: target)) { viewModel.act { await viewModel.ignore(target, of: untracked, localOnly: localOnly) } }
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

/// A repository-relative path, so a rename can also move the file.
struct RenameFileSheet: View {
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
    private var isValid: Bool { !trimmed.isEmpty && trimmed != entry.path && !trimmed.hasSuffix("/") }

    var body: some View {
        GitDialogSheet(
            title: "Rename \(entry.fileName)",
            message: entry.workdirStatus == .untracked
                ? "Include folders in the path to move the file."
                : "Tracked files are renamed with git mv, so the rename is staged.",
            symbol: "pencil",
            primaryTitle: "Rename",
            isPrimaryDisabled: !isValid,
            onCancel: onCancel,
            onPrimary: { onRename(trimmed) }
        ) {
            GitDialogCard {
                GitDialogField("New Path") {
                    TextField("Path", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                        .gitInitialFocus()
                        .onSubmit { if isValid { onRename(trimmed) } }
                }
            }
        }
    }
}

#Preview("Rename") {
    RenameFileSheet(entry: MockData.statusEntries[0], onRename: { _ in }, onCancel: {})
}
#endif
