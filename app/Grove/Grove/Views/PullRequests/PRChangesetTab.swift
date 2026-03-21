// Views/PullRequests/PRChangesetTab.swift
// Grove

import SwiftUI

// MARK: - PRChangesetTab

/// The "Files" tab inside ``PullRequestDetailView``.
///
/// Shows all files changed across the entire pull request, with their status
/// icons and proportional addition/deletion change bars. Clicking a file
/// expands an inline diff viewer below it.
///
/// The changeset is loaded lazily when the tab is first shown.
struct PRChangesetTab: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingChangeset {
            loadingState
        } else if viewModel.prChangeset.isEmpty {
            emptyState
        } else {
            changesetContent
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView("Loading changeset\u{2026}")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No file changes found")
                .foregroundStyle(.secondary)
            Text("Changed files across all commits in the PR will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Changeset Content

    private var changesetContent: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            fileList
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack {
            Text("\(viewModel.prChangeset.count) file\(viewModel.prChangeset.count == 1 ? "" : "s") changed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            let totalAdditions = viewModel.prChangeset.reduce(0) { $0 + $1.stats.additions }
            let totalDeletions = viewModel.prChangeset.reduce(0) { $0 + $1.stats.deletions }
            Text("+\(totalAdditions) \u{2212}\(totalDeletions)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: selectedPathBinding) {
            ForEach(viewModel.prChangeset, id: \.path) { fileDiff in
                VStack(alignment: .leading, spacing: 0) {
                    ChangesetFileRow(
                        fileDiff: fileDiff,
                        isSelected: viewModel.selectedChangesetFile?.path == fileDiff.path
                    )
                    .tag(fileDiff.path)

                    // Inline diff expansion
                    if viewModel.selectedChangesetFile?.path == fileDiff.path,
                       let diff = fileDiff.diff {
                        InlineCommitDiffView(diff: diff)
                            .transition(.opacity)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: viewModel.selectedChangesetFile?.path)
    }

    // MARK: - Helpers

    private var selectedPathBinding: Binding<String?> {
        Binding {
            viewModel.selectedChangesetFile?.path
        } set: { path in
            if let path {
                viewModel.selectChangesetFile(viewModel.prChangeset.first { $0.path == path })
            } else {
                viewModel.selectChangesetFile(nil)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    vm.selectedPR = MockData.pullRequests[0]
    vm.prChangeset = MockData.commitFileDiffs

    return PRChangesetTab()
        .environment(vm)
        .frame(width: 480, height: 420)
}
