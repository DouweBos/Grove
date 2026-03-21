// Views/History/CommitTreeTab.swift
// Grove
//
// Shows the full file tree of the repository at the selected commit,
// built from the commit's changeset (FileDiff entries).
// Directories are collapsible nodes; files are leaves with a status icon
// and can be clicked to select the file diff for inline diff expansion.
// Design ref: CommitDetailPanel "Tree" tab.

import SwiftUI

// MARK: - CommitTreeTab

/// Tree-structured view of the files changed in the selected commit.
///
/// Groups the ``FileDiff`` entries from ``HistoryViewModel/commitDiffs``
/// by directory path, presenting them as a collapsible tree of folders
/// and file leaves.
///
/// Consumes ``HistoryViewModel`` from the environment.
struct CommitTreeTab: View {

    // MARK: Environment

    @Environment(HistoryViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        if viewModel.isLoadingDiff {
            VStack {
                Spacer()
                ProgressView("Loading tree…")
                    .controlSize(.regular)
                Spacer()
            }
        } else if viewModel.commitDiffs.isEmpty {
            VStack {
                Spacer()
                Text("No changes")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                statsBar
                Divider()
                treeList
            }
        }
    }

    // MARK: Stats Bar

    private var statsBar: some View {
        HStack {
            Text("\(viewModel.commitDiffs.count) file\(viewModel.commitDiffs.count == 1 ? "" : "s") changed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("+\(totalAdditions) −\(totalDeletions)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Tree List

    private var treeList: some View {
        CommitFileTree(
            groups: treeGroups,
            selectedPath: viewModel.selectedFileDiff?.path
        ) { fileDiff in
            viewModel.selectFileDiff(fileDiff)
        }
    }

    // MARK: Tree Building

    /// Groups diffs by their parent directory, sorted root-first.
    private var treeGroups: [CommitTreeGroup] {
        var grouped: [String: [FileDiff]] = [:]

        for diff in viewModel.commitDiffs {
            let url = URL(fileURLWithPath: diff.path)
            let dir = url.deletingLastPathComponent().path
            let key = dir == "." ? "" : dir
            grouped[key, default: []].append(diff)
        }

        return grouped
            .sorted { lhs, rhs in
                if lhs.key.isEmpty { return true }
                if rhs.key.isEmpty { return false }
                return lhs.key < rhs.key
            }
            .map { CommitTreeGroup(directory: $0.key, diffs: $0.value) }
    }

    // MARK: Helpers

    private var totalAdditions: Int {
        viewModel.commitDiffs.reduce(0) { $0 + $1.stats.additions }
    }

    private var totalDeletions: Int {
        viewModel.commitDiffs.reduce(0) { $0 + $1.stats.deletions }
    }
}

// MARK: - CommitTreeGroup

/// One directory node in the commit file tree.
struct CommitTreeGroup {
    let directory: String
    let diffs: [FileDiff]
}

// MARK: - CommitFileTree

/// Scrollable tree rendering a list of ``CommitTreeGroup`` values.
private struct CommitFileTree: View {

    // MARK: Properties

    let groups: [CommitTreeGroup]
    let selectedPath: String?
    let onSelect: (FileDiff) -> Void

    // MARK: State

    @State private var expandedDirectories: Set<String> = []

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups, id: \.directory) { group in
                    if group.directory.isEmpty {
                        // Root-level files — shown without a folder header
                        ForEach(group.diffs, id: \.path) { diff in
                            commitFileRow(diff, indent: 0)
                        }
                    } else {
                        directorySection(group)
                    }
                }
            }
        }
        .listStyle(.plain)
        .onAppear { expandAll() }
    }

    // MARK: Directory Section

    private func directorySection(_ group: CommitTreeGroup) -> some View {
        let isExpanded = expandedDirectories.contains(group.directory)
        return VStack(spacing: 0) {
            // Folder header
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

                    Text("\(group.diffs.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.06))

            Divider()

            // Child file rows
            if isExpanded {
                ForEach(group.diffs, id: \.path) { diff in
                    commitFileRow(diff, indent: 20)
                }
            }
        }
    }

    // MARK: File Row

    private func commitFileRow(_ diff: FileDiff, indent: CGFloat) -> some View {
        let isSelected = selectedPath == diff.path
        return HStack(spacing: 6) {
            // Indent spacer
            if indent > 0 {
                Spacer()
                    .frame(width: indent)
            }

            // Status icon
            commitStatusIcon(diff.status)
                .frame(width: 14)

            // File name
            Text((diff.path as NSString).lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .primary)

            Spacer()

            // Change bar
            ChangeBar(additions: diff.stats.additions, deletions: diff.stats.deletions)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(diff) }
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Status Icon

    @ViewBuilder
    private func commitStatusIcon(_ status: FileStatus) -> some View {
        switch status {
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
        case .renamed:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
        case .copied:
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(.blue)
        default:
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func expandAll() {
        let dirs = groups.map(\.directory).filter { !$0.isEmpty }
        expandedDirectories = Set(dirs)
    }
}

// MARK: - Preview

#Preview("Commit Tree Tab") {
    let vm = HistoryViewModel(repository: MockGitRepository())
    vm.selectedCommit = MockData.commits[0]
    vm.commitDiffs = MockData.commitFileDiffs

    return CommitTreeTab()
        .environment(vm)
        .frame(width: 360, height: 500)
}
