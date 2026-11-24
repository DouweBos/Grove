// BranchesReview/ReviewParts.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// A summary tile: coloured label, large number, mono footnote; a filter when clicked.
struct ReviewTile: View {
    @Environment(\.gitStyle) private var style
    let title: String
    let symbol: String
    let color: Color
    let value: String
    var footnote: String?
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
                Label(title, systemImage: symbol)
                    .font(style.font(12, .medium))
                    .foregroundStyle(color)
                Text(value)
                    .font(style.font(30, .medium, .rounded))
                    .foregroundStyle(style.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let footnote {
                    Text(footnote).font(style.monoCaption).foregroundStyle(style.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gitCard()
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous).strokeBorder(color, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .gitClickable()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A local branch to review: checkbox, name, last commit and its standing.
struct ReviewRow: View {
    @Environment(\.gitStyle) private var style
    let branch: ReviewedBranch
    let staleDays: Int
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!branch.isDeletable)
                .opacity(branch.isDeletable ? 1 : 0.3)
                .accessibilityLabel("Select \(branch.name)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: GitMetrics.Spacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(style.font(11, .semibold))
                        .foregroundStyle(style.textSecondary)
                    Text(branch.name)
                        .font(style.font(13, .medium))
                        .foregroundStyle(style.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: GitMetrics.Spacing.sm) {
                    Text(String(branch.sha.prefix(7)))
                    if !branch.authorName.isEmpty { Text(branch.authorName).lineLimit(1) }
                    if let date = branch.lastCommitDate { Text(date, format: .relative(presentation: .named)).lineLimit(1) }
                    Text(branch.lastCommitSummary).lineLimit(1)
                }
                .font(style.monoCaption)
                .foregroundStyle(style.textSecondary)
            }
            Spacer(minLength: GitMetrics.Spacing.md)
            badges
        }
    }

    private var badges: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            if branch.isCurrentBranch {
                GitStatusBadge(title: "Current", symbol: "checkmark", tone: .neutral)
            }
            if let worktreePath = branch.worktreePath {
                GitStatusBadge(title: "In Worktree", symbol: "tree", tone: .neutral)
                    .help("Checked out in \(abbreviatingHome(worktreePath)); remove that worktree to delete it.")
            }
            switch branch.category {
            case .merged: GitStatusBadge(title: "Merged", symbol: "checkmark.circle.fill", tone: .positive)
            case .stale: GitStatusBadge(title: "Stale \(branch.daysSinceLastCommit ?? staleDays)d", symbol: "moon.zzz.fill", tone: .caution)
            case .active: EmptyView()
            }
            if branch.ahead > 0 {
                GitStatusBadge(title: "Ahead \(branch.ahead)", symbol: "arrow.up", tone: .neutral)
            }
            if branch.behind > 0 {
                GitStatusBadge(title: "Behind \(branch.behind)", symbol: "arrow.down", tone: branch.behind > 50 ? .caution : .neutral)
            }
        }
        .fixedSize()
    }
}
#endif
