// WorkingCopy/FileStatusRow.swift
// GroveUIKit
//
// One file in the Staged and Changes sections: stage checkbox, status letter, path.

#if os(macOS)
import GroveKit
import SwiftUI

struct FileStatusRow: View {
    @Environment(\.gitStyle) private var style
    let entry: StatusEntry
    /// The status for the section this row sits in (index status when staged, workdir otherwise).
    let status: FileStatus
    let isStaged: Bool
    let isSelected: Bool
    /// Tree mode already shows the directory in a group header.
    var showsDirectory = true
    /// Stored through Git LFS, so its diff is a pointer rather than content.
    var isLFS = false
    /// The app's, at the trailing edge.
    var accessory: AnyView?
    var onToggleStage: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if let onToggleStage {
                Button(action: onToggleStage) {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(style.font(14))
                        .foregroundStyle(isStaged ? style.accent : style.textSecondary)
                }
                .buttonStyle(.plain)
                .gitClickable()
                .help(isStaged ? "Unstage" : "Stage")
                .accessibilityLabel(isStaged ? "Unstage \(entry.fileName)" : "Stage \(entry.fileName)")
            }
            GitStatusIcon(status: status)
            pathLabel
            Spacer(minLength: 0)
            if let accessory { accessory }
            if isLFS {
                Text("LFS")
                    .font(style.font(9, .bold))
                    .foregroundStyle(style.info)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(style.info.opacity(0.14), in: Capsule())
                    .help("Stored with Git LFS")
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.vertical, 5)
        .background(background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous))
        .contentShape(Rectangle())
        .gitClickable()
        .onHover { isHovered = $0 }
    }

    private var pathLabel: some View {
        let name = Text(entry.fileName).fontWeight(.semibold).foregroundColor(style.textPrimary)
        let label = showsDirectory && !entry.directory.isEmpty
            ? Text(entry.directory).foregroundColor(style.textSecondary) + name
            : name
        return label
            .font(style.font(13, .regular, .monospaced))
            .lineLimit(1)
            .truncationMode(.head)
            .help(entry.path)
    }

    private var background: Color {
        if isSelected { return style.selectionFill }
        return isHovered ? style.surfaceRaised : .clear
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(Array(MockData.statusEntries.prefix(5).enumerated()), id: \.offset) { index, entry in
            FileStatusRow(entry: entry, status: entry.workdirStatus, isStaged: index.isMultiple(of: 2),
                          isSelected: index == 1, isLFS: index == 2, onToggleStage: {})
        }
    }
    .padding(8)
    .frame(width: 320)
    .gitPanel()
    .padding()
}
#endif
