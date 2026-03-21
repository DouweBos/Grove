// Views/BranchesReview/BranchesReviewView.swift
// Grove

import SwiftUI

// MARK: - BranchesReviewView

/// The Branches Review screen — categorised list of local branches.
///
/// Shows all local branches grouped into Active, Stale, and Merged sections.
/// Supports batch deletion of selected stale/merged branches. Injected with
/// a ``BranchesReviewViewModel`` via `@Environment`.
struct BranchesReviewView: View {

    @Environment(BranchesReviewViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Branches Review")
                .font(.headline)

            Spacer()

            // Summary counts
            if !viewModel.branches.isEmpty {
                branchCountSummary
            }

            // Delete selected button
            if viewModel.deletableCount > 0 {
                Button(role: .destructive) {
                    Task { await viewModel.deleteSelected() }
                } label: {
                    if viewModel.isDeletingBranches {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            "Delete \(viewModel.deletableCount) Branch\(viewModel.deletableCount == 1 ? "" : "es")",
                            systemImage: "trash"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDeletingBranches)
            }

            // Refresh button
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .help("Refresh branch list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Branch Count Summary

    private var branchCountSummary: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.groupedBranches, id: \.category) { group in
                let (color, _): (Color, String) = {
                    switch group.category {
                    case .active:  return (.green, "Active")
                    case .stale:   return (.orange, "Stale")
                    case .merged:  return (.blue, "Merged")
                    }
                }()
                Text("\(group.branches.count) \(group.category.rawValue)")
                    .font(.caption)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.1), in: Capsule())
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.branches.isEmpty {
            VStack {
                Spacer()
                ProgressView("Analysing branches\u{2026}")
                Spacer()
            }
        } else if viewModel.branches.isEmpty {
            emptyState
        } else {
            branchList
        }
    }

    // MARK: - Branch List

    private var branchList: some View {
        List {
            // Error banner
            if let error = viewModel.errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(viewModel.groupedBranches, id: \.category) { group in
                Section {
                    BranchReviewSection(
                        category: group.category,
                        branches: group.branches,
                        selectedBranches: viewModel.selectedBranches,
                        onToggle: { branch in viewModel.toggleSelection(for: branch) }
                    )
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No local branches")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Local branches will appear here once they are created.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    let vm = BranchesReviewViewModel(repository: MockGitRepository())
    return BranchesReviewView()
        .environment(vm)
        .frame(width: 700, height: 500)
        .task { await vm.refresh() }
}
