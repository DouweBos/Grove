// Views/WorkingCopy/FileStatusListView.swift
// Grove
//
// Scrollable file list for the bottom-left zone of the Working Copy layout.
// Shows all changed files with staging checkboxes, status icons, and a
// FileStatusToolbar at the top (Stage All / Unstage All + file count +
// view mode picker).

import SwiftUI

// MARK: - FileStatusListView

/// The file list component occupying the bottom-left pane of the Working Copy.
///
/// Consumes ``WorkingCopyViewModel`` from the environment.
struct FileStatusListView: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            FileStatusToolbar()
            Divider()
            fileList
        }
    }

    // MARK: File List

    @ViewBuilder
    private var fileList: some View {
        // The All Files mode shows the full tracked-file tree regardless of
        // whether there are any current changes, so bypass the empty-state guard.
        if viewModel.fileViewMode == .allFiles {
            allFilesTree
        } else {
            let entries = displayedEntries
            if entries.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    systemImage: viewModel.showOnlyConflicts ? "checkmark.circle" : "checkmark.seal",
                    title: viewModel.showOnlyConflicts ? "No Conflicts" : "Nothing to Commit",
                    subtitle: viewModel.showOnlyConflicts
                        ? "All conflicts have been resolved."
                        : "Your working tree is clean."
                )
            } else {
                switch viewModel.fileViewMode {
                case .flatModified:
                    flatFileList(entries: entries)
                case .treeModified:
                    TreeFileList(entries: entries)
                case .allFiles:
                    allFilesTree  // unreachable; handled above
                }
            }
        }
    }

    // MARK: Flat List

    private func flatFileList(entries: [StatusEntry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    FileStatusRow(
                        entry: entry,
                        isSelected: viewModel.selectedEntry?.id == entry.id
                    ) {
                        Task { await toggleStage(entry: entry) }
                    }
                    .onTapGesture {
                        Task { await viewModel.select(entry) }
                    }
                    .contextMenu {
                        contextMenu(for: entry)
                    }

                    Divider()
                        .padding(.leading, 34)
                }
            }
        }
    }

    // MARK: All Files Tree

    private var allFilesTree: some View {
        AllFilesTreeView(
            trackedPaths: viewModel.allTrackedFiles,
            statusEntries: viewModel.statusEntries
        )
    }

    // MARK: Context Menu

    @ViewBuilder
    private func contextMenu(for entry: StatusEntry) -> some View {
        if entry.indexStatus != .unmodified {
            Button("Unstage") {
                Task { await viewModel.unstageFile(entry) }
            }
        } else {
            Button("Stage") {
                Task { await viewModel.stageFile(entry) }
            }
        }
        Divider()
        Button("Discard Changes", role: .destructive) {
            Task { await viewModel.discardFile(entry) }
        }
    }

    // MARK: Helpers

    /// Entries filtered by the `showOnlyConflicts` toggle from `ConflictBannerView`.
    private var displayedEntries: [StatusEntry] {
        if viewModel.showOnlyConflicts {
            return viewModel.statusEntries.filter {
                $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted
            }
        }
        return viewModel.statusEntries
    }

    private func toggleStage(entry: StatusEntry) async {
        if entry.indexStatus != .unmodified {
            await viewModel.unstageFile(entry)
        } else {
            await viewModel.stageFile(entry)
        }
    }
}

// MARK: - FileStatusToolbar

/// Compact toolbar above the file list with Stage All/Unstage All,
/// a file-count label, and the ``FileViewMode`` picker.
struct FileStatusToolbar: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Top row: count label + stage/unstage button
            HStack(spacing: 6) {
                fileCountLabel
                Spacer()
                stageAllButton
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Mode picker row
            Picker("View Mode", selection: modeBinding) {
                ForEach(FileViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .background(Color(white: 0.15, opacity: 1))
    }

    // MARK: Sub-views

    private var fileCountLabel: some View {
        let count = viewModel.statusEntries.count
        return Text("\(count) Changed \(count == 1 ? "File" : "Files")")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var stageAllButton: some View {
        let hasStagedFiles = !viewModel.stagedFiles.isEmpty
        let hasUnstagedFiles = !viewModel.unstagedFiles.isEmpty

        if hasStagedFiles && !hasUnstagedFiles {
            Button("Unstage All") {
                Task { await viewModel.unstageAll() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Stage All") {
                Task { await viewModel.stageAll() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: Helpers

    private var modeBinding: Binding<FileViewMode> {
        Binding(
            get: { viewModel.fileViewMode },
            set: { viewModel.fileViewMode = $0 }
        )
    }
}

// MARK: - TreeFileList

/// Groups ``StatusEntry`` values into a collapsible directory tree.
///
/// Each directory node is independently expandable. Files at the root level
/// are shown without a folder parent node.
private struct TreeFileList: View {

    // MARK: Properties

    let entries: [StatusEntry]

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: State

    @State private var expandedDirectories: Set<String> = []

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(treeGroups, id: \.directory) { group in
                    if group.directory.isEmpty {
                        // Root-level files — no folder header
                        ForEach(group.entries) { entry in
                            fileRow(entry)
                        }
                    } else {
                        // Directory group with collapsible header
                        directorySection(group)
                    }
                }
            }
        }
        .onAppear { expandAll() }
    }

    // MARK: Sub-views

    private func directorySection(_ group: TreeGroup) -> some View {
        let isExpanded = expandedDirectories.contains(group.directory)
        return VStack(spacing: 0) {
            // Directory header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedDirectories.remove(group.directory)
                    } else {
                        expandedDirectories.insert(group.directory)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0x58 / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0))

                    Text(group.directory)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Text("\(group.entries.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.14))

            Divider()

            // Files inside directory
            if isExpanded {
                ForEach(group.entries) { entry in
                    fileRow(entry, indent: 16)
                }
            }
        }
    }

    private func fileRow(_ entry: StatusEntry, indent: CGFloat = 0) -> some View {
        FileStatusRow(
            entry: entry,
            isSelected: viewModel.selectedEntry?.id == entry.id
        ) {
            Task { await toggleStage(entry: entry) }
        }
        .padding(.leading, indent)
        .onTapGesture {
            Task { await viewModel.select(entry) }
        }
        .overlay(
            Divider()
                .padding(.leading, 34 + indent),
            alignment: .bottom
        )
    }

    // MARK: Tree Building

    private struct TreeGroup {
        let directory: String
        let entries: [StatusEntry]
    }

    private var treeGroups: [TreeGroup] {
        var grouped: [String: [StatusEntry]] = [:]

        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            let dir = url.deletingLastPathComponent().path
            let key = dir == "." ? "" : dir
            grouped[key, default: []].append(entry)
        }

        // Sort: root first, then alphabetically by directory
        return grouped
            .sorted { lhs, rhs in
                if lhs.key.isEmpty { return true }
                if rhs.key.isEmpty { return false }
                return lhs.key < rhs.key
            }
            .map { TreeGroup(directory: $0.key, entries: $0.value) }
    }

    // MARK: Helpers

    private func expandAll() {
        let dirs = treeGroups.map(\.directory).filter { !$0.isEmpty }
        expandedDirectories = Set(dirs)
    }

    private func toggleStage(entry: StatusEntry) async {
        if entry.indexStatus != .unmodified {
            await viewModel.unstageFile(entry)
        } else {
            await viewModel.stageFile(entry)
        }
    }
}

// MARK: - AllFilesTreeView

/// Displays every tracked file in the repository as a collapsible directory tree.
///
/// Unlike ``TreeFileList`` (which only shows changed files), this view operates
/// on the full `git ls-files` output. Files that also appear in `statusEntries`
/// show their status icon pair; unmodified tracked files show a neutral file icon.
private struct AllFilesTreeView: View {

    // MARK: Properties

    /// All paths returned by `git ls-files`, sorted alphabetically.
    let trackedPaths: [String]
    /// Current status entries — used to overlay change indicators on modified files.
    let statusEntries: [StatusEntry]

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: State

    @State private var expandedDirectories: Set<String> = []

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(treeGroups, id: \.directory) { group in
                    if group.directory.isEmpty {
                        ForEach(group.filenames, id: \.self) { filename in
                            allFilesRow(path: filename, indent: 0)
                        }
                    } else {
                        allFilesDirectorySection(group)
                    }
                }
            }
        }
        .onAppear { expandAll() }
    }

    // MARK: Sub-views

    private func allFilesDirectorySection(_ group: AllFilesGroup) -> some View {
        let isExpanded = expandedDirectories.contains(group.directory)
        return VStack(spacing: 0) {
            // Directory header — mirrors TreeFileList style.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedDirectories.remove(group.directory)
                    } else {
                        expandedDirectories.insert(group.directory)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0x58 / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0))

                    Text(group.directory)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Text("\(group.filenames.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.14))

            Divider()

            if isExpanded {
                ForEach(group.filenames, id: \.self) { filename in
                    let fullPath = group.directory.isEmpty ? filename : "\(group.directory)/\(filename)"
                    allFilesRow(path: fullPath, indent: 16)
                }
            }
        }
    }

    /// A single row for a tracked file, with optional status indicators when the
    /// file has changes in the working tree or index.
    private func allFilesRow(path: String, indent: CGFloat) -> some View {
        let statusEntry = statusEntryIndex[path]
        let isSelected  = viewModel.selectedEntry?.id == path
        let filename    = URL(fileURLWithPath: path).lastPathComponent

        return HStack(spacing: 6) {
            // Placeholder to align with checkbox column in FileStatusRow.
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(.clear)
                .frame(width: 20, height: 20)

            // Status icons: real pair for changed files, neutral for clean files.
            if let entry = statusEntry {
                HStack(spacing: 2) {
                    StatusIcon(status: entry.indexStatus)
                    StatusIcon(status: entry.workdirStatus)
                }
            } else {
                HStack(spacing: 2) {
                    StatusIcon(status: .unmodified)
                    StatusIcon(status: .unmodified)
                }
            }

            Text(filename)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, indent)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let entry = statusEntry else { return }
            Task { await viewModel.select(entry) }
        }
        .overlay(
            Divider().padding(.leading, 34 + indent),
            alignment: .bottom
        )
    }

    // MARK: Tree Building

    private struct AllFilesGroup {
        /// Directory component (relative path from repo root), or `""` for root files.
        let directory: String
        /// Bare file names within this directory.
        let filenames: [String]
    }

    private var treeGroups: [AllFilesGroup] {
        var grouped: [String: [String]] = [:]

        for path in trackedPaths {
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent().path
            let key = dir == "." ? "" : dir
            let filename = url.lastPathComponent
            grouped[key, default: []].append(filename)
        }

        return grouped
            .sorted { lhs, rhs in
                if lhs.key.isEmpty { return true }
                if rhs.key.isEmpty { return false }
                return lhs.key < rhs.key
            }
            .map { key, filenames in
                AllFilesGroup(directory: key, filenames: filenames.sorted())
            }
    }

    /// O(1) lookup from path → StatusEntry, built once per render pass.
    private var statusEntryIndex: [String: StatusEntry] {
        Dictionary(uniqueKeysWithValues: statusEntries.map { ($0.path, $0) })
    }

    // MARK: Helpers

    private func expandAll() {
        let dirs = treeGroups.map(\.directory).filter { !$0.isEmpty }
        expandedDirectories = Set(dirs)
    }
}

// MARK: - Preview

#Preview("File Status List") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    FileStatusListView()
        .environment(vm)
        .frame(width: 280, height: 400)
        .task { await vm.refresh() }
}

#Preview("File Status List — Tree Mode") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    vm.fileViewMode = .treeModified
    return FileStatusListView()
        .environment(vm)
        .frame(width: 280, height: 400)
        .task { await vm.refresh() }
}

#Preview("File Status List — All Files") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    vm.fileViewMode = .allFiles
    return FileStatusListView()
        .environment(vm)
        .frame(width: 280, height: 500)
        .task { await vm.refresh() }
}
