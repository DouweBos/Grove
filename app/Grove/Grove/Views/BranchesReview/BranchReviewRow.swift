// Views/BranchesReview/BranchReviewRow.swift
// Grove

import SwiftUI

// MARK: - BranchReviewRow

/// A single row in the Branches Review list.
///
/// Shows a selection checkbox, branch name (with current-branch star), category
/// badge, last-activity date, and ahead/behind counts relative to the primary branch.
struct BranchReviewRow: View {

    let branch: ReviewedBranch
    let isSelected: Bool
    let onToggle: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox (disabled for the current branch)
            if branch.isCurrentBranch {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                    .frame(width: 16, alignment: .center)
                    .help("Currently checked-out branch")
            } else {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.system(size: 14))
                    .frame(width: 16, alignment: .center)
                    .onTapGesture { onToggle() }
            }

            // Branch name
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label(branch.name, systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Category badge
                    categoryBadge
                }

                HStack(spacing: 8) {
                    // Author
                    Text(branch.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Ahead/behind counts
                    aheadBehindView

                    // Last activity date
                    if branch.lastCommitDate > Date.distantPast {
                        Text(branch.lastCommitDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Category Badge

    @ViewBuilder
    private var categoryBadge: some View {
        let (label, color) = categoryAppearance
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var categoryAppearance: (String, Color) {
        switch branch.category {
        case .active:   return ("Active", .green)
        case .stale:    return ("Stale", .orange)
        case .merged:   return ("Merged", .blue)
        }
    }

    // MARK: - Ahead / Behind

    @ViewBuilder
    private var aheadBehindView: some View {
        if branch.aheadOfMain > 0 || branch.behindMain > 0 {
            HStack(spacing: 4) {
                if branch.aheadOfMain > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(branch.aheadOfMain)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.green)
                }
                if branch.behindMain > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(branch.behindMain)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let branches: [ReviewedBranch] = [
        ReviewedBranch(
            id: "refs/heads/main",
            name: "main",
            isCurrentBranch: true,
            lastCommitDate: Date(),
            authorName: "Jane Developer",
            authorEmail: "jane@example.com",
            aheadOfMain: 0,
            behindMain: 0,
            category: .active
        ),
        ReviewedBranch(
            id: "refs/heads/feature/auth",
            name: "feature/auth",
            isCurrentBranch: false,
            lastCommitDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            authorName: "Bob Contributor",
            authorEmail: "bob@example.com",
            aheadOfMain: 3,
            behindMain: 0,
            category: .active
        ),
        ReviewedBranch(
            id: "refs/heads/old-experiment",
            name: "old-experiment",
            isCurrentBranch: false,
            lastCommitDate: Calendar.current.date(byAdding: .day, value: -45, to: Date())!,
            authorName: "Alice Reviewer",
            authorEmail: "alice@example.com",
            aheadOfMain: 2,
            behindMain: 5,
            category: .stale
        ),
        ReviewedBranch(
            id: "refs/heads/hotfix/issue-99",
            name: "hotfix/issue-99",
            isCurrentBranch: false,
            lastCommitDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            authorName: "Jane Developer",
            authorEmail: "jane@example.com",
            aheadOfMain: 0,
            behindMain: 2,
            category: .merged
        ),
    ]

    return List {
        ForEach(branches) { branch in
            BranchReviewRow(
                branch: branch,
                isSelected: branch.name == "old-experiment",
                onToggle: {}
            )
        }
    }
    .listStyle(.plain)
    .frame(width: 420, height: 200)
}
