// Primitives/GitStatusIcon.swift
// GroveUIKit
//
// Colored badge displaying a single-character file status code (M / A / D / ? / U / R / C).
// Shown as a staged/unstaged pair in the Working Copy file list.

#if os(macOS)
import GroveKit
import SwiftUI

// MARK: - GitStatusIcon

/// A fixed-size rounded-rectangle badge showing a status letter with semantic color.
///
/// Usage:
/// ```swift
/// GitStatusIcon(status: entry.indexStatus)
/// GitStatusIcon(status: entry.workdirStatus)
/// ```
public struct GitStatusIcon: View {

    // MARK: Properties

    @Environment(\.gitStyle) private var style
    private let status: FileStatus

    public init(status: FileStatus) {
        self.status = status
    }

    // MARK: Body

    public var body: some View {
        Text(label)
            .font(style.font(10, .bold, .monospaced))
            .foregroundStyle(color)
            .frame(width: 16 * style.fontScale, height: 16 * style.fontScale)
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
        case .unmodified:          return style.textSecondary
        case .modified:            return style.info
        case .added:               return style.success
        case .deleted:             return style.danger
        case .renamed, .copied:    return style.renamed
        case .untracked, .ignored: return style.textSecondary
        case .conflicted:          return style.warning
        case .typeChange:          return style.renamed
        }
    }
}

// MARK: - Preview

#Preview("Status Icons") {
    HStack(spacing: 8) {
        ForEach(FileStatus.allCases, id: \.self) { status in
            VStack(spacing: 4) {
                GitStatusIcon(status: status)
                Text(status.rawValue)
                    .font(.caption2)
            }
        }
    }
    .padding()
    .background(GitUIStyle.system.surface)
}
#endif
