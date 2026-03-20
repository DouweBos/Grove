// Views/WorkingCopy/DiffPanelView.swift
// Grove
//
// The right-hand diff panel of the Working Copy layout. Shows a file header
// with Staged / Unstaged toggle buttons, then a scrollable DiffView.

import SwiftUI
import Foundation

// MARK: - DiffPanelView

/// Right-hand panel displaying the diff for the currently selected file.
///
/// Consumes ``WorkingCopyViewModel`` from the environment.
struct DiffPanelView: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            diffContent
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            // File name
            if let entry = viewModel.selectedEntry {
                fileNameLabel(entry)
            } else {
                Text("No File Selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Staged / Unstaged toggle
            stagedUnstagedPicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.15, opacity: 1))
    }

    private func fileNameLabel(_ entry: StatusEntry) -> some View {
        HStack(spacing: 6) {
            StatusIcon(status: viewModel.showingStaged ? entry.indexStatus : entry.workdirStatus)

            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                let dir = URL(fileURLWithPath: entry.path)
                    .deletingLastPathComponent().path
                if dir != "." {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }

    // MARK: Staged / Unstaged Picker

    private var stagedUnstagedPicker: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Staged", isActive: viewModel.showingStaged) {
                if !viewModel.showingStaged {
                    Task { await viewModel.toggleStagedUnstaged() }
                }
            }
            toggleButton(title: "Unstaged", isActive: !viewModel.showingStaged) {
                if viewModel.showingStaged {
                    Task { await viewModel.toggleStagedUnstaged() }
                }
            }
        }
        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private func toggleButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.85)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(isActive ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Diff Content

    @ViewBuilder
    private var diffContent: some View {
        if viewModel.isDiffLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedEntry == nil {
            EmptyStateView(
                systemImage: "doc.text.magnifyingglass",
                title: "Select a File",
                subtitle: "Choose a file from the list to view its diff."
            )
        } else if let diff = viewModel.currentDiff {
            ScrollView([.horizontal, .vertical]) {
                DiffView(
                    diff: diff,
                    showingStaged: viewModel.showingStaged
                ) { hunk, action in
                    guard let entry = viewModel.selectedEntry else { return }
                    Task { await viewModel.performHunkAction(action, hunk: hunk, in: entry) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.11))
        } else {
            EmptyStateView(
                systemImage: "doc.questionmark",
                title: "No Diff Available",
                subtitle: "The diff for this file could not be loaded."
            )
        }
    }
}

// MARK: - Preview

#Preview("Diff Panel") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    DiffPanelView()
        .environment(vm)
        .frame(width: 600, height: 500)
        .task {
            await vm.refresh()
            if let first = vm.statusEntries.first {
                await vm.select(first)
            }
        }
}
