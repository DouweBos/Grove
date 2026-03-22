// Views/Diff/DiffHeaderView.swift
// Grove
//
// Reusable diff panel header bar showing file name, status icon, stats bar,
// and Staged/Unstaged toggle. Extracted so History and Stash detail panels
// can reuse it independently of WorkingCopyViewModel.

import SwiftUI
import Foundation

// MARK: - DiffHeaderView

/// A header bar for any diff panel displaying a single file diff.
///
/// Used standalone in the History commit detail inline diff expansion and
/// in the Stash detail view. The Working Copy diff panel (`DiffPanelView`)
/// has its own header built into the view; this component is for other contexts.
struct DiffHeaderView: View {

    // MARK: Properties

    let filePath: String
    let stats: DiffStats
    var showStagedToggle: Bool = false
    var isStaged: Bool = false
    var onToggleStaged: (() -> Void)?

    // MARK: Body

    var body: some View {
        HStack(spacing: 8) {
            // File path
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                let dir = URL(fileURLWithPath: filePath)
                    .deletingLastPathComponent().path
                if dir != "." {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            // Change bar
            DiffStatsBar(stats: stats, width: 40)

            // +/- counts
            statsLabel

            Spacer()

            // Optional staged/unstaged toggle
            if showStagedToggle {
                stagedToggle
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.15, opacity: 1))
    }

    // MARK: Sub-views

    private var statsLabel: some View {
        HStack(spacing: 4) {
            Text("+\(stats.additions)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(red: 0x2E / 255.0, green: 0xA0 / 255.0, blue: 0x43 / 255.0))
            Text("-\(stats.deletions)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(red: 0xF8 / 255.0, green: 0x51 / 255.0, blue: 0x49 / 255.0))
        }
    }

    private var stagedToggle: some View {
        HStack(spacing: 0) {
            segmentButton("Staged", isActive: isStaged) {
                if !isStaged { onToggleStaged?() }
            }
            segmentButton("Unstaged", isActive: !isStaged) {
                if isStaged { onToggleStaged?() }
            }
        }
        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private func segmentButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isActive ? Color.accentColor.opacity(0.85) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(isActive ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Diff Header") {
    VStack(spacing: 1) {
        DiffHeaderView(
            filePath: "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
            stats: DiffStats(additions: 18, deletions: 7),
            showStagedToggle: true,
            isStaged: true
        )
        Divider()
        DiffHeaderView(
            filePath: "README.md",
            stats: DiffStats(additions: 0, deletions: 3)
        )
    }
    .frame(width: 600)
    .background(Color(white: 0.11))
}
