// Components/StatusIcon.swift
// Grove
//
// Colored badge displaying a single-character file status code (M / A / D / ? / U / R / C).
// Shown as a staged/unstaged pair in the Working Copy file list.

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
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
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
        case .unmodified:            return .clear
        case .modified:              return Color(hex: 0xE07B35)  // orange — unstaged
        case .added:                 return Color(hex: 0x2EA043)  // green — new
        case .deleted:               return Color(hex: 0xF85149)  // red — removed
        case .renamed:               return Color(hex: 0x58A6FF)  // blue
        case .copied:                return Color(hex: 0x58A6FF)  // blue
        case .untracked:             return Color(hex: 0x8B949E)  // gray
        case .ignored:               return Color(hex: 0x6E7681)  // dim gray
        case .conflicted:            return Color(hex: 0xD29922)  // amber
        case .typeChange:            return Color(hex: 0xBC8CFF)  // purple
        }
    }
}

// MARK: - Color Hex Initialiser (private helper)

extension Color {
    /// Initialise from a 24-bit hex literal, e.g. `Color(hex: 0x2EA043)`.
    fileprivate init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
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
}
