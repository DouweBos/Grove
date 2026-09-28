// Views/History/ChangesetFileRow.swift
// Grove

import SwiftUI

/// A changed file in a commit: disclosure chevron, status badge, path, and line stats.
struct ChangesetFileRow: View {
    let fileDiff: FileDiff
    var isExpanded = false
    /// Stashes and pull requests drive expansion through List selection instead of `onToggle`.
    var isSelected = false
    var onToggle: (() -> Void)?

    var body: some View {
        if let onToggle {
            Button(action: onToggle) { content }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapse diff" : "Expand diff")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(isExpanded || isSelected ? 90 : 0))
                .frame(width: 10)
            CommitFileStatusBadge(status: fileDiff.status)
            pathText
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Theme.Spacing.sm)
            DiffStatsLabel(stats: fileDiff.stats)
            DiffStatsBar(stats: fileDiff.stats, width: 44)
        }
        .padding(.horizontal, onToggle == nil ? 0 : Theme.Spacing.lg)
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    /// Directory in secondary color so the file name stands out.
    private var pathText: Text {
        let path = fileDiff.path as NSString
        let directory = path.deletingLastPathComponent
        let name = Text(path.lastPathComponent).foregroundStyle(Theme.textPrimary)
        let full = directory.isEmpty ? name : Text(directory + "/").foregroundStyle(Theme.textSecondary) + name
        return full.font(.system(size: 13))
    }
}

/// Single-letter file status (A / M / D / R …) on a tinted square.
struct CommitFileStatusBadge: View {
    let status: FileStatus

    var body: some View {
        Text(status == .unmodified ? "·" : status.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 17, height: 17)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(String(describing: status))
    }

    private var color: Color {
        switch status {
        case .added: Theme.added
        case .deleted: Theme.deleted
        case .modified, .typeChange: Theme.modified
        case .renamed, .copied: Theme.renamed
        case .conflicted: Theme.conflicted
        case .untracked, .ignored, .unmodified: Theme.untracked
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(MockData.commitFileDiffs, id: \.path) { diff in
            ChangesetFileRow(fileDiff: diff, isExpanded: diff.path == MockData.commitFileDiffs.first?.path) {}
        }
    }
    .frame(width: 520)
    .panel()
    .padding()
    .background(Theme.background)
}
