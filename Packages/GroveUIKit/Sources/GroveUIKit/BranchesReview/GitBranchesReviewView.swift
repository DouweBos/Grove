// BranchesReview/GitBranchesReviewView.swift
// GroveUIKit
//
// Summary tiles (merged, stale, active) above a checklist of local branches to clean up in bulk.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitBranchesReviewView: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var host
    private let viewModel: BranchesReviewViewModel

    /// Deletes through the view model's `commands`, only where `GitFeature.editBranches` is supported.
    public init(viewModel: BranchesReviewViewModel) {
        self.viewModel = viewModel
    }

    private var canDelete: Bool { viewModel.canDelete && features.contains(.editBranches) }

    public var body: some View {
        VStack(spacing: GitMetrics.Spacing.md) {
            if let error = viewModel.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: error, tone: .negative) { viewModel.dismissError() }
            }
            HStack(spacing: GitMetrics.Spacing.md) {
                ForEach(BranchCategory.allCases, id: \.self) { category in
                    ReviewTile(title: category.rawValue, symbol: category.symbol, color: category.color(style),
                               value: "\(viewModel.count(of: category))", footnote: footnote(category),
                               isSelected: viewModel.categoryFilter == category) { viewModel.toggleFilter(category) }
                }
            }
            if let warning = viewModel.mergeStatusWarning {
                GitBanner(symbol: "exclamationmark.triangle",
                          message: "Couldn't check which branches are merged into \(viewModel.primaryBranch), so deleting is off. \(warning)",
                          tone: .negative, actionTitle: "Retry", action: { Task { await viewModel.refresh() } },
                          onDismiss: viewModel.dismissMergeStatusWarning)
            }
            listPanel
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { viewModel.pendingDelete != nil },
                                                              set: { if !$0 { viewModel.cancelDelete() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingDelete) { pending in
            Button(pending.needsForce ? "Force Delete" : "Delete", role: .destructive) {
                Task {
                    viewModel.dismissError()
                    await viewModel.confirmDelete(pending)
                }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: { pending in
            let subject = pending.branches.count == 1 ? "This branch is" : "These branches are"
            Text(pending.needsForce
                 ? "Not everything here is merged into \(viewModel.primaryBranch); unmerged commits stay reachable only through the reflog. Undo restores the branches."
                 : "\(subject) fully merged into \(viewModel.primaryBranch). Undo restores them.")
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
        guard let pending = viewModel.pendingDelete else { return "" }
        return pending.branches.count == 1 ? "Delete \u{201C}\(pending.branches[0].name)\u{201D}?" : "Delete \(pending.branches.count) branches?"
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: viewModel.categoryFilter.map { "\($0.rawValue) Branches" } ?? "Local Branches",
                           detail: "\(viewModel.visibleBranches.count) \u{00B7} vs \(viewModel.primaryBranch)") {
                if viewModel.isLoading { ProgressView().controlSize(.small) }
                if viewModel.selectedIDs.isEmpty {
                    Button("Select All") { viewModel.selectAllVisible() }
                        .disabled(!viewModel.visibleBranches.contains(where: \.isDeletable))
                } else {
                    Button("Deselect") { viewModel.clearSelection() }
                    Button("Delete \(viewModel.selectedIDs.count)", role: .destructive) { viewModel.requestDelete(viewModel.selectedBranches) }
                        .buttonStyle(.borderedProminent)
                        .tint(style.danger)
                        .disabled(!canDelete)
                        .requires(.editBranches)
                }
                Button { Task { await viewModel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                    .accessibilityLabel("Refresh")
            }
            .buttonStyle(.borderless)
            .gitClickable()
            .controlSize(.small)
            if viewModel.branches.isEmpty && viewModel.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleBranches.isEmpty {
                GitEmptyState(systemImage: "checkmark.seal", title: "Nothing Here",
                              subtitle: viewModel.categoryFilter == nil ? "No local branches." : "No branches in this group.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.visibleBranches) { branch in
                            ReviewRow(branch: branch, staleDays: viewModel.staleDays,
                                      isChecked: viewModel.selectedIDs.contains(branch.id)) { viewModel.toggleSelection(branch) }
                                .gitSelectableRow(isSelected: viewModel.selectedIDs.contains(branch.id))
                                .onTapGesture { if branch.isDeletable { viewModel.toggleSelection(branch) } }
                                .gitClickable(branch.isDeletable)
                                .contextMenu {
                                    Button("Delete \u{201C}\(branch.name)\u{201D}", systemImage: "trash", role: .destructive) {
                                        viewModel.requestDelete([branch])
                                    }
                                    .disabled(!branch.isDeletable || !canDelete)
                                    Button("Copy Name", systemImage: "doc.on.doc") { host.copy(branch.name) }
                                }
                        }
                    }
                    .padding(GitMetrics.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .gitPanel()
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

    func color(_ style: GitUIStyle) -> Color {
        switch self {
        case .merged: style.success
        case .stale: style.warning
        case .active: style.info
        }
    }
}
#endif
