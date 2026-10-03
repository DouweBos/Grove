// Components/DiffStatsBar.swift
// Grove
//
// Compact bar showing the additions/deletions ratio of a file or commit.

import GroveKit
import SwiftUI

struct DiffStatsBar: View {
    let stats: DiffStats
    var width: CGFloat = 60
    var height: CGFloat = 6

    var body: some View {
        let total = CGFloat(stats.additions + stats.deletions)
        HStack(spacing: total > 0 && stats.additions > 0 && stats.deletions > 0 ? 1 : 0) {
            if total == 0 {
                Capsule().fill(Theme.track)
            } else {
                if stats.additions > 0 {
                    Capsule().fill(Theme.added).frame(width: max(width * CGFloat(stats.additions) / total, height))
                }
                if stats.deletions > 0 {
                    Capsule().fill(Theme.deleted)
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("\(stats.additions) additions, \(stats.deletions) deletions")
    }
}

/// "+12 −3" in mono caption with semantic colors.
struct DiffStatsLabel: View {
    let stats: DiffStats

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("+\(stats.additions)").foregroundStyle(Theme.added)
            Text("\u{2212}\(stats.deletions)").foregroundStyle(Theme.deleted)
        }
        .font(.monoCaption)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        DiffStatsBar(stats: DiffStats(additions: 18, deletions: 7))
        DiffStatsBar(stats: DiffStats(additions: 0, deletions: 5))
        DiffStatsBar(stats: DiffStats(additions: 42, deletions: 0))
        DiffStatsBar(stats: DiffStats(additions: 0, deletions: 0))
        DiffStatsLabel(stats: DiffStats(additions: 42, deletions: 3))
    }
    .padding()
    .background(Theme.surface)
}
