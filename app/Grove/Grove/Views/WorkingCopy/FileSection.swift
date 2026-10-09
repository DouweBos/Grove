// Views/WorkingCopy/FileSection.swift
// Grove

import AppKit
import GroveKit
import SwiftUI

/// A labelled group of rows; flat or grouped by directory depending on the view mode.
struct FileSection<Accessory: View>: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @AppStorage(GrovePreferences.Key.diffToolPath) private var diffToolPath = ""
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""

    let title: String
    let entries: [StatusEntry]
    let side: DiffSide
    /// `nil` for conflicts, which are resolved rather than staged.
    let isStagedSection: Bool?
    let focusList: () -> Void
    let recordFrame: (CGRect, FileRow) -> Void
    @ViewBuilder var accessory: () -> Accessory

    /// Rows are direct children of the list's lazy stack, so only the visible ones are built.
    var body: some View {
        SectionLabel(title: title, count: entries.count, accessory: accessory)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
        if viewModel.fileViewMode == .treeModified {
            ForEach(viewModel.directoryGroups(entries), id: \.directory) { group in
                if !group.directory.isEmpty {
                    directoryHeader(group.directory)
                }
                ForEach(group.entries) { entry in
                    row(entry, showsDirectory: false)
                        .padding(.leading, group.directory.isEmpty ? 0 : Theme.Spacing.lg)
                }
            }
        } else {
            ForEach(entries) { row($0, showsDirectory: true) }
        }
        Color.clear.frame(height: Theme.Spacing.md - 2)
    }

    private func row(_ entry: StatusEntry, showsDirectory: Bool) -> some View {
        let status = entry.isConflicted ? FileStatus.conflicted : (side == .staged ? entry.indexStatus : entry.workdirStatus)
        return FileStatusRow(
            entry: entry,
            status: status,
            isStaged: isStagedSection ?? false,
            isSelected: viewModel.isSelected(entry, side: side),
            showsDirectory: showsDirectory,
            isLFS: viewModel.isLFS(entry),
            onToggleStage: isStagedSection.map { staged in
                { Task { staged ? await viewModel.unstageFile(entry) : await viewModel.stageFile(entry) } }
            }
        )
        .onTapGesture {
            focusList()
            let modifiers = NSEvent.modifierFlags
            Task {
                await viewModel.click(entry, side: side, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FileStatusListView.coordinateSpace)) } action: {
            recordFrame($0, FileRow(path: entry.path, side: side))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.path)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await viewModel.select(entry, side: side) } }
        .contextMenu { contextMenu(for: entry) }
    }

    private func directoryHeader(_ directory: String) -> some View {
        Label {
            Text(directory).font(.monoCaption).lineLimit(1).truncationMode(.head)
        } icon: {
            Image(systemName: "folder").font(.system(size: 11))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func contextMenu(for entry: StatusEntry) -> some View {
        // Right-clicking inside a multi-selection acts on all of it.
        let entries = viewModel.actionEntries(for: entry, side: side)
        if let staged = isStagedSection {
            let row = FileRow(path: entry.path, side: side)
            // Right-clicking inside a multi-selection acts on this section's part of it.
            let rows: Set<FileRow> = viewModel.fileSelection.contains(row) ? viewModel.fileSelection.rows.filter { $0.side == side } : [row]
            Button(rows.count > 1 ? "\(staged ? "Unstage" : "Stage") \(rows.count) Files" : (staged ? "Unstage" : "Stage")) {
                Task { await viewModel.toggleStage(rows) }
            }
            if !diffToolPath.isEmpty, entries.count == 1 {
                Button("Open in Diff Tool") { Task { await viewModel.openInDiffTool(entry, side: side) } }
            }
            let patchEntries = viewModel.patchEntries(for: entry, side: side)
            Button(patchEntries.count > 1 ? "Create Patch from \(patchEntries.count) Files\u{2026}" : "Create Patch\u{2026}") {
                Task { await savePatch(patchEntries, side: side, viewModel: viewModel) }
            }
        } else if entries.count == 1 {
            Button("Resolve…") { Task { await viewModel.select(entry) } }
            if !mergeToolPath.isEmpty {
                Button("Open in Merge Tool") { Task { await viewModel.openInMergeTool(entry) } }
            }
        }
        let lfsCandidates = viewModel.lfsCandidates(entries)
        if !lfsCandidates.isEmpty {
            Menu("Track with Git LFS") {
                Button(lfsCandidates.count > 1 ? "These \(lfsCandidates.count) Files" : "This File") {
                    Task { await viewModel.trackWithLFS(lfsCandidates, byExtension: false) }
                }
                if let pattern = WorkingCopyViewModel.lfsExtensionPattern(for: lfsCandidates) {
                    Button("All \(pattern) Files") { Task { await viewModel.trackWithLFS(lfsCandidates, byExtension: true) } }
                }
            }
        }
        Divider()
        Button(entries.count > 1 ? "Copy \(entries.count) Paths" : "Copy Path") {
            GroveClipboard.copy(entries.map(\.path).joined(separator: "\n"))
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(entries.map { viewModel.repository.path.appendingPathComponent($0.path) })
        }
        Divider()
        FileActionsMenu(entries: entries)
        Divider()
        Button(entries.count > 1 ? "Discard Changes in \(entries.count) Files…" : "Discard Changes…", role: .destructive) {
            viewModel.requestDiscard(entries)
        }
    }

}

extension FileSection where Accessory == EmptyView {
    init(title: String, entries: [StatusEntry], side: DiffSide, isStagedSection: Bool?, focusList: @escaping () -> Void,
         recordFrame: @escaping (CGRect, FileRow) -> Void) {
        self.init(title: title, entries: entries, side: side, isStagedSection: isStagedSection, focusList: focusList,
                  recordFrame: recordFrame) { EmptyView() }
    }
}
