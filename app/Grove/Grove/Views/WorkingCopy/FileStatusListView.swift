// Views/WorkingCopy/FileStatusListView.swift
// Grove
//
// Scrollable file list for the bottom-left zone of the Working Copy layout.
// Shows all changed files with staging checkboxes, status icons, and a
// Stage All / Unstage All toolbar button at the top.

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
            toolbar
            Divider()
            fileList
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack {
            Text("Status")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Filename")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            stageAllButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(white: 0.15, opacity: 1))
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

    // MARK: File List

    @ViewBuilder
    private var fileList: some View {
        if viewModel.statusEntries.isEmpty && !viewModel.isLoading {
            EmptyStateView(
                systemImage: "checkmark.seal",
                title: "Nothing to Commit",
                subtitle: "Your working tree is clean."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.statusEntries) { entry in
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

    private func toggleStage(entry: StatusEntry) async {
        if entry.indexStatus != .unmodified {
            await viewModel.unstageFile(entry)
        } else {
            await viewModel.stageFile(entry)
        }
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
