// Views/WorkingCopy/FileStatusRow.swift
// Grove
//
// A single row in the file status list. Shows dual status icons (staged +
// unstaged), a checkbox for staging, and the file path.
// Orange/green icon pairs, file names truncated.

import SwiftUI
import Foundation

// MARK: - FileStatusRow

/// One row in the ``FileStatusListView``.
///
/// The leading pair of ``StatusIcon`` badges shows the staged (index) status
/// on the left and the unstaged (working directory) status on the right,
/// as a pair of status icons.
struct FileStatusRow: View {

    // MARK: Properties

    let entry: StatusEntry
    let isSelected: Bool
    var onToggleStage: (() -> Void)?

    // MARK: Computed

    private var isStaged: Bool { entry.indexStatus != .unmodified }
    private var hasUnstagedChanges: Bool { entry.workdirStatus != .unmodified }

    private var filename: String {
        URL(fileURLWithPath: entry.path).lastPathComponent
    }

    private var directory: String {
        let url = URL(fileURLWithPath: entry.path)
        let dir = url.deletingLastPathComponent().path
        return dir == "." ? "" : dir
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 6) {
            // Staging checkbox
            checkboxButton

            // Dual status icons
            HStack(spacing: 2) {
                StatusIcon(status: entry.indexStatus)
                StatusIcon(status: entry.workdirStatus)
            }

            // File name + directory path
            filePathLabel

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    // MARK: Sub-views

    private var checkboxButton: some View {
        Button {
            onToggleStage?()
        } label: {
            Image(systemName: checkboxImageName)
                .font(.system(size: 13))
                .foregroundStyle(checkboxColor)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
    }

    private var filePathLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(filename)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !directory.isEmpty {
                Text(directory)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    // MARK: Helpers

    private var checkboxImageName: String {
        if isStaged && !hasUnstagedChanges {
            return "checkmark.square.fill"
        } else if isStaged {
            return "minus.square.fill"  // partially staged
        } else {
            return "square"
        }
    }

    private var checkboxColor: Color {
        if isStaged {
            return Color(red: 0x2E / 255.0, green: 0xA0 / 255.0, blue: 0x43 / 255.0)
        } else {
            return .secondary
        }
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.2) : .clear
    }
}

// MARK: - Preview

#Preview("File Status Row") {
    let entries = MockData.statusEntries.prefix(4)
    VStack(spacing: 0) {
        ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
            FileStatusRow(entry: entry, isSelected: idx == 1)
            Divider()
        }
    }
    .frame(width: 300)
    .background(Color(white: 0.11))
}
