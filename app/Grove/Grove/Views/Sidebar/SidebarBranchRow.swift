// Views/Sidebar/SidebarBranchRow.swift
// Grove

import SwiftUI

/// A single branch row in the sidebar, showing the branch name and ahead/behind counts.
struct SidebarBranchRow: View {

    let branch: BranchInfo
    /// When `true`, a small pin icon is shown to indicate the branch is pinned.
    var isPinned: Bool = false

    /// The short display name — strips the group prefix for grouped branches.
    var displayName: String {
        if let slashIndex = branch.name.firstIndex(of: "/") {
            return String(branch.name[branch.name.index(after: slashIndex)...])
        }
        return branch.name
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isHEAD ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(branch.isHEAD ? Theme.accent : Theme.textSecondary)
                .frame(width: 16)

            Text(displayName)
                .fontWeight(branch.isHEAD ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if isPinned {
                Image(systemName: "pin.fill")
                    .imageScale(.small)
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(45))
            }

            if branch.ahead > 0 || branch.behind > 0 {
                AheadBehindIndicator(ahead: branch.ahead, behind: branch.behind)
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - AheadBehindIndicator

/// Compact "N : M" ahead/behind display.
private struct AheadBehindIndicator: View {

    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 2) {
            if ahead > 0 {
                Image(systemName: "arrow.up")
                    .imageScale(.small)
                Text("\(ahead)")
            }
            if ahead > 0 && behind > 0 {
                Text(":")
            }
            if behind > 0 {
                Image(systemName: "arrow.down")
                    .imageScale(.small)
                Text("\(behind)")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
    }
}

#Preview {
    List {
        SidebarBranchRow(branch: MockData.branches[0])
        SidebarBranchRow(branch: MockData.branches[1])
        SidebarBranchRow(branch: MockData.branches[2])
        SidebarBranchRow(branch: MockData.branches[4])
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 160)
}
