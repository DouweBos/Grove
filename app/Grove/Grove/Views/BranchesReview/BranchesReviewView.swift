// Views/BranchesReview/BranchesReviewView.swift
// Grove

import SwiftUI

/// Summary tiles (merged / stale / active) above a checklist of local branches.
struct BranchesReviewView: View {

    @Environment(BranchesReviewViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(BranchCategory.allCases, id: \.self) { category in
                    StatCard(title: category.rawValue, symbol: category.symbol, color: category.color,
                             value: "\(viewModel.count(of: category))", footnote: footnote(category),
                             isSelected: viewModel.categoryFilter == category) {
                        viewModel.toggleFilter(category)
                    }
                }
            }
            if let mergeStatusError = viewModel.mergeStatusError {
                Banner(symbol: "exclamationmark.triangle",
                       message: "Couldn't check which branches are merged into \(viewModel.primaryBranch), so deleting is disabled. \(mergeStatusError)",
                       tone: .negative, actionTitle: "Retry", action: { Task { await viewModel.refresh() } })
            }
            listPanel
        }
        .padding(.bottom, Theme.Spacing.md)
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { viewModel.pendingDelete != nil },
                                                              set: { if !$0 { viewModel.cancelDelete() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingDelete) { pending in
            Button(pending.needsForce ? "Force Delete" : "Delete", role: .destructive) {
                Task { await viewModel.confirmDelete(pending) }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: { pending in
            let subject = pending.branches.count == 1 ? "This branch is" : "These branches are"
            Text(pending.needsForce
                 ? "Not everything here is merged into \(viewModel.primaryBranch); unmerged commits stay reachable only through the reflog. Edit \u{203A} Undo restores the branches."
                 : "\(subject) fully merged into \(viewModel.primaryBranch). Edit \u{203A} Undo restores them.")
        }
        .alert("Couldn't Delete Some Branches", isPresented: Binding(get: { viewModel.errorMessage != nil },
                                                                    set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func footnote(_ category: BranchCategory) -> String {
        switch category {
        case .merged: "in \(viewModel.primaryBranch), safe to delete"
        case .stale: "no commits in \(viewModel.staleDays)d"
        case .active: "recent or current work"
        }
    }

    private var deleteTitle: String {
        let count = viewModel.pendingDelete?.branches.count ?? 0
        return count == 1 ? "Delete \u{201C}\(viewModel.pendingDelete!.branches[0].name)\u{201D}?" : "Delete \(count) branches?"
    }

    // MARK: - List

    private var listPanel: some View {
        VStack(spacing: 0) {
            PanelHeader(title: viewModel.categoryFilter.map { "\($0.rawValue) Branches" } ?? "Local Branches",
                        detail: "\(viewModel.visibleBranches.count) \u{00B7} vs \(viewModel.primaryBranch)") {
                if viewModel.isLoading { ProgressView().controlSize(.small) }
                if viewModel.selectedIDs.isEmpty {
                    Button("Select All") { viewModel.selectAllVisible() }
                        .disabled(!viewModel.visibleBranches.contains(where: \.isDeletable))
                } else {
                    Button("Deselect") { viewModel.clearSelection() }
                    Button("Delete \(viewModel.selectedIDs.count)\u{2026}", role: .destructive) {
                        viewModel.requestDelete(viewModel.selectedBranches)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .disabled(!viewModel.canDelete)
                }
                Button { Task { await viewModel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            if viewModel.branches.isEmpty && viewModel.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleBranches.isEmpty {
                EmptyStateView(systemImage: "checkmark.seal", title: "Nothing Here",
                               subtitle: viewModel.categoryFilter == nil ? "No local branches." : "No branches in this group.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.visibleBranches) { branch in
                            BranchReviewRow(branch: branch, staleDays: viewModel.staleDays,
                                            isChecked: viewModel.selectedIDs.contains(branch.id)) {
                                viewModel.toggleSelection(branch)
                            }
                            .selectableRow(isSelected: viewModel.selectedIDs.contains(branch.id))
                            .onTapGesture { viewModel.toggleSelection(branch) }
                            .contextMenu {
                                Button("Delete \u{201C}\(branch.name)\u{201D}\u{2026}", systemImage: "trash", role: .destructive) {
                                    viewModel.requestDelete([branch])
                                }
                                .disabled(!branch.isDeletable || !viewModel.canDelete)
                                Button("Copy Name", systemImage: "doc.on.doc") { GroveClipboard.copy(branch.name) }
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panel()
    }
}

// MARK: - Row

private struct BranchReviewRow: View {
    let branch: ReviewedBranch
    let staleDays: Int
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!branch.isDeletable)
                .opacity(branch.isDeletable ? 1 : 0.3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(branch.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Text(String(branch.sha.prefix(7)))
                    if !branch.authorName.isEmpty { Text(branch.authorName).lineLimit(1) }
                    if let date = branch.lastCommitDate { Text(date, format: .relative(presentation: .named)) }
                    Text(branch.lastCommitSummary).lineLimit(1)
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            badges
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if branch.isCurrentBranch {
                StatusBadge(title: "Current", symbol: "checkmark", tone: .neutral)
            }
            switch branch.category {
            case .merged: StatusBadge(title: "Merged", symbol: "checkmark.circle.fill", tone: .positive)
            case .stale: StatusBadge(title: "Stale \(branch.daysSinceLastCommit ?? staleDays)d", symbol: "moon.zzz.fill", tone: .caution)
            case .active: EmptyView()
            }
            if branch.ahead > 0 {
                StatusBadge(title: "Ahead \(branch.ahead)", symbol: "arrow.up", tone: .neutral)
            }
            if branch.behind > 0 {
                StatusBadge(title: "Behind \(branch.behind)", symbol: "arrow.down", tone: branch.behind > 50 ? .caution : .neutral)
            }
        }
    }
}

extension BranchCategory {
    var symbol: String {
        switch self {
        case .merged: "checkmark.circle.fill"
        case .stale: "moon.zzz.fill"
        case .active: "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .merged: Theme.success
        case .stale: Theme.warning
        case .active: Theme.info
        }
    }
}

#Preview {
    let vm = BranchesReviewViewModel(repository: MockGitRepository())
    return BranchesReviewView()
        .environment(vm)
        .frame(width: 900, height: 600)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
