// Components/ChangeBar.swift
// Grove
//
// A compact horizontal bar visualising the additions/deletions ratio for a file.
// Used in History commit detail (changeset tab) and Working Copy file list.
// Green segment for additions, red for deletions.
//
// NOTE: ChangesetFileRow.swift (WS4) defines a similarly-named local ChangeBar.
// This component provides the same visual but takes a DiffStats value type
// and is used across WS3 components. WS5 integration will consolidate.

import SwiftUI

// MARK: - DiffStatsBar

/// A fixed-width proportional bar showing green (additions) and red (deletions)
/// segments derived from a ``DiffStats`` value.
///
/// Prefer this over constructing a custom bar — it uses the canonical diff palette.
struct DiffStatsBar: View {

    // MARK: Properties

    let stats: DiffStats
    /// Total visual width of the bar in points.
    var width: CGFloat = 60
    /// Height of the bar in points.
    var height: CGFloat = 8

    // MARK: Body

    var body: some View {
        HStack(spacing: 1) {
            if stats.additions == 0 && stats.deletions == 0 {
                emptySegment
            } else {
                if additionFraction > 0 {
                    segment(color: .addition, fraction: additionFraction)
                }
                if deletionFraction > 0 {
                    segment(color: .deletion, fraction: deletionFraction)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .frame(width: width, height: height)
    }

    // MARK: Private

    private var total: Double {
        Double(stats.additions + stats.deletions)
    }

    private var additionFraction: Double {
        total > 0 ? Double(stats.additions) / total : 0
    }

    private var deletionFraction: Double {
        total > 0 ? Double(stats.deletions) / total : 0
    }

    private func segment(color: Color, fraction: Double) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width * fraction - 1, 2))
    }

    private var emptySegment: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: width)
    }
}

// MARK: - Semantic Colors

private extension Color {
    static let addition = Color(red: 0x2E / 255, green: 0xA0 / 255, blue: 0x43 / 255)
    static let deletion  = Color(red: 0xF8 / 255, green: 0x51 / 255, blue: 0x49 / 255)
}

// MARK: - Preview

#Preview("Diff Stats Bar") {
    VStack(alignment: .leading, spacing: 12) {
        DiffStatsBar(stats: DiffStats(additions: 18, deletions: 7))
        DiffStatsBar(stats: DiffStats(additions: 0,  deletions: 5))
        DiffStatsBar(stats: DiffStats(additions: 42, deletions: 0))
        DiffStatsBar(stats: DiffStats(additions: 0,  deletions: 0))
        DiffStatsBar(stats: DiffStats(additions: 1,  deletions: 99))
    }
    .padding()
}
