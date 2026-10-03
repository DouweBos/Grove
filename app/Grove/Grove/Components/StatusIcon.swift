// Components/StatusIcon.swift
// Grove
//
// Colored badge displaying a single-character file status code (M / A / D / ? / U / R / C).
// Shown as a staged/unstaged pair in the Working Copy file list.

import GroveKit
import SwiftUI

// MARK: - StatusIcon

/// A fixed-size rounded-rectangle badge showing a status letter with semantic color.
///
/// Usage:
/// ```swift
/// StatusIcon(status: entry.indexStatus)
/// StatusIcon(status: entry.workdirStatus)
/// ```
struct StatusIcon: View {

    // MARK: Properties

    let status: FileStatus

    // MARK: Body

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(status == .unmodified ? Color.clear : color.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(Text(verbatim: "\(status)"))
    }

    // MARK: Private

    private var label: String {
        switch status {
        case .unmodified: return " "
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .renamed:    return "R"
        case .copied:     return "C"
        case .untracked:  return "?"
        case .ignored:    return "!"
        case .conflicted: return "U"
        case .typeChange: return "T"
        }
    }

    private var color: Color {
        switch status {
        case .unmodified:          return Theme.textSecondary
        case .modified:            return Theme.modified
        case .added:               return Theme.added
        case .deleted:             return Theme.deleted
        case .renamed, .copied:    return Theme.renamed
        case .untracked, .ignored: return Theme.untracked
        case .conflicted:          return Theme.conflicted
        case .typeChange:          return Theme.renamed
        }
    }
}

// MARK: - Preview

#Preview("Status Icons") {
    HStack(spacing: 8) {
        ForEach(FileStatus.allCases, id: \.self) { status in
            VStack(spacing: 4) {
                StatusIcon(status: status)
                Text(status.rawValue)
                    .font(.caption2)
            }
        }
    }
    .padding()
    .background(Theme.surface)
}
