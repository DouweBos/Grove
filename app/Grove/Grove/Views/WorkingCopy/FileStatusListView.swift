// Views/WorkingCopy/FileStatusListView.swift
// Grove
//
// File list panel: Conflicts / Staged / Changes sections. A partially
// staged file appears in both Staged and Changes, each row acting on its own half.

import AppKit
import SwiftUI

struct FileStatusListView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", detail: fileCountDetail) {
                viewModePicker
            }
            content
        }
        .panel()
    }

    private var fileCountDetail: String? {
        let count = viewModel.statusEntries.count
        return count == 0 ? nil : "\(count) changed"
    }

    private var viewModePicker: some View {
        Menu {
            Picker("View", selection: Binding(get: { viewModel.fileViewMode }, set: { mode in Task { await viewModel.setFileViewMode(mode) } })) {
                ForEach(FileViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: viewModel.fileViewMode.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.textSecondary)
        .help("View Mode")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.fileViewMode == .allFiles {
            AllFilesTreeView()
        } else if viewModel.statusEntries.isEmpty {
            if !viewModel.hasLoadedStatus {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The diff panel carries the big "Nothing to Commit" state.
                Text("No changed files")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    sections
                }
                .padding(Theme.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        let conflicts = viewModel.conflictedFiles
        if !conflicts.isEmpty {
            FileSection(title: "Conflicts", entries: conflicts, side: .unstaged, isStagedSection: nil)
        }
        if !viewModel.showOnlyConflicts {
            let staged = viewModel.stagedFiles
            if !staged.isEmpty {
                FileSection(title: "Staged", entries: staged, side: .staged, isStagedSection: true) {
                    sectionButton("Unstage All") { await viewModel.unstageAll() }
                }
            }
            let unstaged = viewModel.unstagedFiles
            if !unstaged.isEmpty {
                FileSection(title: "Changes", entries: unstaged, side: .unstaged, isStagedSection: false) {
                    sectionButton("Stage All") { await viewModel.stageAll() }
                }
            }
        }
    }

    private func sectionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - FileSection

/// A labelled group of rows; flat or grouped by directory depending on the view mode.
private struct FileSection<Accessory: View>: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @AppStorage(GrovePreferences.Key.diffToolPath) private var diffToolPath = ""
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""

    let title: String
    let entries: [StatusEntry]
    let side: DiffSide
    /// `nil` for conflicts, which are resolved rather than staged.
    let isStagedSection: Bool?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title: title, count: entries.count, accessory: accessory)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)
            if viewModel.fileViewMode == .treeModified {
                ForEach(directoryGroups, id: \.directory) { group in
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
        }
    }

    private func row(_ entry: StatusEntry, showsDirectory: Bool) -> some View {
        let status = entry.isConflicted ? FileStatus.conflicted : (side == .staged ? entry.indexStatus : entry.workdirStatus)
        return FileStatusRow(
            entry: entry,
            status: status,
            isStaged: isStagedSection ?? false,
            isSelected: viewModel.isSelected(entry, side: side),
            showsDirectory: showsDirectory,
            onToggleStage: isStagedSection.map { staged in
                { Task { staged ? await viewModel.unstageFile(entry) : await viewModel.stageFile(entry) } }
            }
        )
        .onTapGesture { Task { await viewModel.select(entry, side: side) } }
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
        if let staged = isStagedSection {
            Button(staged ? "Unstage" : "Stage") {
                Task { staged ? await viewModel.unstageFile(entry) : await viewModel.stageFile(entry) }
            }
            if !diffToolPath.isEmpty {
                Button("Open in Diff Tool") { Task { await viewModel.openInDiffTool(entry, side: side) } }
            }
        } else {
            Button("Resolve…") { Task { await viewModel.select(entry) } }
            if !mergeToolPath.isEmpty {
                Button("Open in Merge Tool") { Task { await viewModel.openInMergeTool(entry) } }
            }
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([viewModel.repository.path.appendingPathComponent(entry.path)])
        }
        Divider()
        Button("Discard Changes…", role: .destructive) { viewModel.requestDiscard(entry) }
    }

    private struct DirectoryGroup {
        let directory: String
        let entries: [StatusEntry]
    }

    private var directoryGroups: [DirectoryGroup] {
        Dictionary(grouping: entries, by: \.directory)
            .sorted { $0.key < $1.key }
            .map { DirectoryGroup(directory: $0.key, entries: $0.value) }
    }
}

extension FileSection where Accessory == EmptyView {
    init(title: String, entries: [StatusEntry], side: DiffSide, isStagedSection: Bool?) {
        self.init(title: title, entries: entries, side: side, isStagedSection: isStagedSection) { EmptyView() }
    }
}

#Preview("File List") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    FileStatusListView()
        .environment(vm)
        .frame(width: 320, height: 480)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
