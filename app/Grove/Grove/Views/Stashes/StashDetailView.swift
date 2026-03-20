// Views/Stashes/StashDetailView.swift
// Grove

import SwiftUI

/// Detail panel for a selected stash — shows metadata, actions, and changeset.
struct StashDetailView: View {

    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        if let stash = viewModel.selectedStash {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                stashHeader(stash)

                Divider()

                // Changeset
                stashChangeset
            }
        } else {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "tray.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select a stash to view its contents")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func stashHeader(_ stash: StashEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action buttons
            HStack(spacing: 8) {
                Button("Apply") {
                    Task { await viewModel.apply(stash: stash) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Pop") {
                    Task { await viewModel.pop(stash: stash) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Drop", role: .destructive) {
                    Task { await viewModel.drop(stash: stash) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Stash info
            VStack(alignment: .leading, spacing: 4) {
                Text(stash.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let branch = stash.branchName {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(stash.sha.prefix(7)))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                    Text(stash.date.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Changeset

    @ViewBuilder
    private var stashChangeset: some View {
        if viewModel.isLoadingDiff {
            VStack {
                Spacer()
                ProgressView("Loading stash contents…")
                Spacer()
            }
        } else if viewModel.stashDiffs.isEmpty {
            VStack {
                Spacer()
                Text("No changes in this stash")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(viewModel.stashDiffs.count) file\(viewModel.stashDiffs.count == 1 ? "" : "s") changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                List(selection: selectionBinding) {
                    ForEach(viewModel.stashDiffs, id: \.path) { fileDiff in
                        VStack(alignment: .leading, spacing: 0) {
                            ChangesetFileRow(
                                fileDiff: fileDiff,
                                isSelected: viewModel.selectedFileDiff?.path == fileDiff.path
                            )
                            .tag(fileDiff.path)

                            if viewModel.selectedFileDiff?.path == fileDiff.path,
                               let diff = fileDiff.diff {
                                InlineCommitDiffView(diff: diff)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: viewModel.selectedFileDiff?.path)
            }
        }
    }

    // MARK: - Helpers

    private var selectionBinding: Binding<String?> {
        Binding {
            viewModel.selectedFileDiff?.path
        } set: { path in
            viewModel.selectedFileDiff = path.flatMap { p in
                viewModel.stashDiffs.first { $0.path == p }
            }
        }
    }
}

#Preview {
    let vm = StashesViewModel(repository: MockGitRepository())
    vm.selectedStash = MockData.stashEntries[0]
    vm.stashDiffs = MockData.commitFileDiffs

    return StashDetailView()
        .environment(vm)
        .frame(width: 400, height: 500)
}
