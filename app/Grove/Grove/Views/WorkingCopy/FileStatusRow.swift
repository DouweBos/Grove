// Views/WorkingCopy/FileStatusRow.swift
// Grove
//
// One file in the Staged / Changes sections: stage checkbox, status letter, path.

import SwiftUI

struct FileStatusRow: View {
    let entry: StatusEntry
    /// The status for the section this row sits in (index status when staged, workdir otherwise).
    let status: FileStatus
    let isStaged: Bool
    let isSelected: Bool
    /// Tree mode already shows the directory in a group header.
    var showsDirectory = true
    var onToggleStage: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let onToggleStage {
                Button(action: onToggleStage) {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(isStaged ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isStaged ? "Unstage" : "Stage")
                .accessibilityLabel(isStaged ? "Unstage \(entry.fileName)" : "Stage \(entry.fileName)")
            }
            StatusIcon(status: status)
            pathLabel
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var pathLabel: some View {
        let name = Text(entry.fileName).fontWeight(.semibold).foregroundColor(Theme.textPrimary)
        let label = showsDirectory && !entry.directory.isEmpty
            ? Text(entry.directory).foregroundColor(Theme.textSecondary) + name
            : name
        return label
            .font(.monoBody)
            .lineLimit(1)
            .truncationMode(.head)
            .help(entry.path)
    }

    private var background: Color {
        if isSelected { return Theme.selectionFill }
        return isHovered ? Theme.surfaceRaised : .clear
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(Array(MockData.statusEntries.prefix(5).enumerated()), id: \.offset) { idx, entry in
            FileStatusRow(entry: entry, status: entry.workdirStatus, isStaged: idx.isMultiple(of: 2),
                          isSelected: idx == 1, onToggleStage: {})
        }
    }
    .padding(Theme.Spacing.sm)
    .frame(width: 320)
    .panel()
    .padding()
    .background(Theme.background)
}
