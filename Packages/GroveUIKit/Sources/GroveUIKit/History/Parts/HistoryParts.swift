// History/Parts/HistoryParts.swift
// GroveUIKit
//
// Small pieces History's panels share: signature badge, line counts, copy button, wrapping row.

#if os(macOS)
import GroveKit
import SwiftUI

/// A commit's signature, nothing when unsigned.
struct VerifiedBadge: View {
    let status: SignatureStatus

    var body: some View {
        switch status {
        case .unsigned: EmptyView()
        case .verified: GitStatusBadge(title: "Verified", symbol: "checkmark.seal.fill", tone: .positive)
        case .unverified: GitStatusBadge(title: "Unverified", symbol: "exclamationmark.triangle.fill", tone: .caution)
        }
    }
}

/// "+12 −3" in mono caption with semantic colors.
struct DiffStatsLabel: View {
    @Environment(\.gitStyle) private var style
    let stats: DiffStats

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            Text("+\(stats.additions)").foregroundStyle(style.success)
            Text("\u{2212}\(stats.deletions)").foregroundStyle(style.danger)
        }
        .font(style.monoCaption)
        .fixedSize()
    }
}

/// The additions/deletions ratio of a file as a short bar.
struct DiffStatsBar: View {
    @Environment(\.gitStyle) private var style
    let stats: DiffStats
    var width: CGFloat = 44
    var height: CGFloat = 6

    var body: some View {
        let total = CGFloat(stats.additions + stats.deletions)
        HStack(spacing: total > 0 && stats.additions > 0 && stats.deletions > 0 ? 1 : 0) {
            if total == 0 {
                Capsule().fill(style.track)
            } else {
                if stats.additions > 0 {
                    Capsule().fill(style.success).frame(width: max(width * CGFloat(stats.additions) / total, height))
                }
                if stats.deletions > 0 { Capsule().fill(style.danger) }
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("\(stats.additions) additions, \(stats.deletions) deletions")
    }
}

/// Single-letter file status (A / M / D / R …) on a tinted square.
struct CommitFileStatusBadge: View {
    @Environment(\.gitStyle) private var style
    let status: FileStatus

    var body: some View {
        Text(status == .unmodified ? "·" : status.rawValue)
            .font(style.font(10, .bold, .monospaced))
            .foregroundStyle(color)
            .frame(width: 17 * style.fontScale, height: 17 * style.fontScale)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(String(describing: status))
    }

    private var color: Color {
        switch status {
        case .added: style.success
        case .deleted: style.danger
        case .modified, .typeChange: style.warning
        case .renamed, .copied: style.renamed
        case .conflicted: style.danger
        case .untracked, .ignored, .unmodified: style.textSecondary
        }
    }
}

/// Copies a value through the host, briefly showing a checkmark.
struct HistoryCopyButton: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var host
    let value: () -> String
    let help: String
    let confirmation: String
    @State private var copied = false

    var body: some View {
        Button {
            host.copy(value())
            host.toast(confirmation)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(style.font(12))
                .foregroundStyle(copied ? style.success : style.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gitClickable()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Wraps its children onto new lines when they don't fit.
struct HistoryFlowRow: Layout {
    var spacing: CGFloat = GitMetrics.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
#endif
