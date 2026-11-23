// History/Detail/CommitDetailPanel.swift
// GroveUIKit
//
// History's right panel: the selected commit's header over its changeset or tree, or what a multi-selection adds up to.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitDetailPanel: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let actions: CommitActions
    private let diffOptions = HistoryDiffOptions()

    var body: some View {
        Group {
            if viewModel.selection.count > 1 {
                CommitSelectionSummary(viewModel: viewModel, actions: actions, commits: viewModel.selectedCommits)
            } else if let commit = viewModel.selectedCommit {
                VStack(spacing: 0) {
                    GitPanelHeader(title: commit.shortSHA) {
                        Picker("View", selection: Binding(get: { viewModel.detailTab }, set: { viewModel.selectDetailTab($0) })) {
                            ForEach(HistoryViewModel.DetailTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .gitClickable()
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            CommitDetailHeader(viewModel: viewModel, commit: commit)
                                .padding(GitMetrics.Spacing.lg)
                            Rectangle().fill(style.border).frame(height: 0.5)
                            switch viewModel.detailTab {
                            case .changeset: changeset(commit)
                            case .tree: CommitTreeTab(viewModel: viewModel, menu: { fileMenu($0, commit: commit) })
                            }
                        }
                    }
                    .id(commit.id)
                }
            } else {
                GitEmptyState(systemImage: "clock.arrow.circlepath", title: "No Commit Selected",
                              subtitle: "Pick a commit to see its changes.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    @ViewBuilder
    private func changeset(_ commit: CommitInfo) -> some View {
        if viewModel.isLoadingDiff {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(GitMetrics.Spacing.xl)
        } else if viewModel.commitDiffs.isEmpty {
            GitEmptyState(systemImage: "doc", title: "No File Changes", subtitle: "This commit doesn't change any files.")
                .frame(height: 220)
        } else {
            changesetSummary
            ChangesetFiles(files: viewModel.commitDiffs, expanded: viewModel.expandedPaths, toggle: { viewModel.toggleFile($0) },
                           options: diffOptions.options, images: .commit(commit.id, in: viewModel.repository),
                           menu: { AnyView(fileMenu($0, commit: commit)) })
        }
    }

    private var changesetSummary: some View {
        let diffs = viewModel.commitDiffs
        let stats = DiffStats(additions: diffs.reduce(0) { $0 + $1.stats.additions },
                              deletions: diffs.reduce(0) { $0 + $1.stats.deletions })
        let allExpanded = viewModel.expandedPaths.count == diffs.count
        return HStack(spacing: GitMetrics.Spacing.sm) {
            GitSectionLabel(title: "\(diffs.count) changed file\(diffs.count == 1 ? "" : "s")").fixedSize()
            DiffStatsLabel(stats: stats)
            Spacer()
            HistoryDiffToggles(options: diffOptions.options)
            Button(allExpanded ? "Collapse All" : "Expand All") { viewModel.setAllFilesExpanded(!allExpanded) }
                .buttonStyle(.borderless)
                .gitClickable()
                .font(style.font(12))
        }
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .padding(.top, GitMetrics.Spacing.md)
        .padding(.bottom, GitMetrics.Spacing.xs)
    }

    @ViewBuilder
    private func fileMenu(_ path: String, commit: CommitInfo) -> some View {
        Button("Show File History") { viewModel.request(.fileHistory(path)) }
        if let blame = viewModel.onOpenBlame {
            Button("Open Blame at This Revision") { Task { await blame(path, commit.id) } }
        }
        Button("Copy Path") { actions.copy(path, "Copied path") }
    }
}
#endif
