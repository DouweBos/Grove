// Views/BranchesReview/BranchReviewSection.swift
// Grove

import SwiftUI

// MARK: - BranchReviewSection

/// A collapsible section grouping branches of a single ``BranchCategory``.
///
/// The section header shows the category name, count, and optional batch-action
/// buttons (Select All / Deselect All) for stale and merged categories.
struct BranchReviewSection: View {

    let category: BranchCategory
    let branches: [ReviewedBranch]
    let selectedBranches: Set<String>
    let onToggle: (ReviewedBranch) -> Void

    @State private var isExpanded = true

    // MARK: - Body

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(branches) { branch in
                BranchReviewRow(
                    branch: branch,
                    isSelected: selectedBranches.contains(branch.id),
                    onToggle: { onToggle(branch) }
                )
                .tag(branch.id)
                .contextMenu {
                    if !branch.isCurrentBranch {
                        Button(selectedBranches.contains(branch.id) ? "Deselect" : "Select") {
                            onToggle(branch)
                        }
                    }
                }
            }
        } label: {
            sectionHeader
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: categoryIcon)
                .foregroundStyle(categoryColor)
                .imageScale(.small)

            Text(category.rawValue)
                .font(.subheadline)
                .fontWeight(.semibold)

            // Count pill
            Text("\(branches.count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: Capsule())

            Spacer()

            // Quick-select buttons for actionable categories
            if category == .stale || category == .merged {
                let selectableBranches = branches.filter { !$0.isCurrentBranch }
                let allSelected = !selectableBranches.isEmpty
                    && selectableBranches.allSatisfy { selectedBranches.contains($0.id) }

                if allSelected {
                    Button("Deselect All") {
                        for branch in selectableBranches { onToggle(branch) }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Button("Select All") {
                        for branch in selectableBranches where !selectedBranches.contains(branch.id) {
                            onToggle(branch)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private var categoryIcon: String {
        switch category {
        case .active:   return "circle.fill"
        case .stale:    return "moon.zzz"
        case .merged:   return "checkmark.circle.fill"
        }
    }

    private var categoryColor: Color {
        switch category {
        case .active:   return .green
        case .stale:    return .orange
        case .merged:   return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    let stale: [ReviewedBranch] = [
        ReviewedBranch(
            id: "refs/heads/old-experiment",
            name: "old-experiment",
            isCurrentBranch: false,
            lastCommitDate: Calendar.current.date(byAdding: .day, value: -50, to: Date())!,
            authorName: "Alice Reviewer",
            authorEmail: "alice@example.com",
            aheadOfMain: 2,
            behindMain: 8,
            category: .stale
        ),
        ReviewedBranch(
            id: "refs/heads/wip/refactor",
            name: "wip/refactor",
            isCurrentBranch: false,
            lastCommitDate: Calendar.current.date(byAdding: .day, value: -60, to: Date())!,
            authorName: "Bob Contributor",
            authorEmail: "bob@example.com",
            aheadOfMain: 0,
            behindMain: 12,
            category: .stale
        )
    ]

    return List {
        BranchReviewSection(
            category: .stale,
            branches: stale,
            selectedBranches: ["refs/heads/wip/refactor"],
            onToggle: { _ in }
        )
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
    .frame(width: 460, height: 160)
}
