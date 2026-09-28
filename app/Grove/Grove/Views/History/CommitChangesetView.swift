// Views/History/CommitChangesetView.swift
// Grove

import SwiftUI

/// Changed files of the selected commit; each row expands into its diff.
/// Emits rows directly so the enclosing LazyVStack can render them lazily.
struct CommitChangesetView: View {
    @Environment(HistoryViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingDiff {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(Theme.Spacing.xl)
        } else if viewModel.commitDiffs.isEmpty {
            EmptyStateView(systemImage: "doc", title: "No File Changes",
                           subtitle: "This commit doesn't change any files.")
                .frame(height: 220)
        } else {
            summary
            ForEach(viewModel.commitDiffs, id: \.path) { file in
                let isExpanded = viewModel.expandedPaths.contains(file.path)
                ChangesetFileRow(fileDiff: file, isExpanded: isExpanded) { viewModel.toggleFile(file.path) }
                    .contextMenu { fileMenu(file.path) }
                if isExpanded {
                    expandedDiff(file)
                }
            }
        }
    }

    private var summary: some View {
        let stats = DiffStats(additions: viewModel.commitDiffs.reduce(0) { $0 + $1.stats.additions },
                              deletions: viewModel.commitDiffs.reduce(0) { $0 + $1.stats.deletions })
        let count = viewModel.commitDiffs.count
        let allExpanded = viewModel.expandedPaths.count == count
        return HStack(spacing: Theme.Spacing.sm) {
            SectionLabel(title: "\(count) changed file\(count == 1 ? "" : "s")")
                .fixedSize()
            DiffStatsLabel(stats: stats)
            Spacer()
            WrapLinesToggle()
            Button(allExpanded ? "Collapse All" : "Expand All") { viewModel.setAllFilesExpanded(!allExpanded) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func expandedDiff(_ file: FileDiff) -> some View {
        Group {
            if ImageDiffView.supports(path: file.path), let sha = viewModel.selectedCommit?.id {
                RepositoryImageDiffView(source: .commit(sha, in: viewModel.repository),
                                        path: file.path, oldPath: file.diff?.oldPath)
                    .frame(height: 360)
            } else if let diff = file.diff, diff.isBinary || !diff.hunks.isEmpty {
                DiffHorizontalScroll { DiffView(diff: diff) }
            } else {
                Text(file.status == .renamed ? "Renamed without content changes." : "No textual changes.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.border, lineWidth: 0.5))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    @ViewBuilder
    private func fileMenu(_ path: String) -> some View {
        Button("Show File History\u{2026}") { viewModel.request(.fileHistory(path)) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return ScrollView { LazyVStack(spacing: 0) { CommitChangesetView() } }
        .environment(vm)
        .frame(width: 520, height: 500)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.loadInitial() }
}
