// Views/Sidebar/SidebarBranchRow.swift
// Grove

import SwiftUI

/// A local branch in the sidebar: name, pin, and ahead/behind counts.
struct SidebarBranchRow: View {

    let branch: BranchInfo
    var isPinned = false
    /// Show the full name instead of the part after the "group/" prefix.
    var showsFullName = false
    /// Another worktree that has this branch checked out.
    var worktree: WorktreeInfo?
    /// Parent recorded when the branch was created.
    var parent: String?

    var displayName: String {
        guard !showsFullName, let slashIndex = branch.name.firstIndex(of: "/") else { return branch.name }
        return String(branch.name[branch.name.index(after: slashIndex)...])
    }

    var body: some View {
        SidebarRow(
            title: displayName,
            symbol: branch.isHEAD ? "checkmark.circle.fill" : (worktree == nil ? "arrow.triangle.branch" : "tree"),
            tint: branch.isHEAD ? Theme.accent : (worktree == nil ? Theme.textSecondary : Theme.info),
            isEmphasized: branch.isHEAD
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(45))
                }
                if branch.ahead > 0 || branch.behind > 0 {
                    AheadBehindIndicator(ahead: branch.ahead, behind: branch.behind)
                }
            }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        var name = branch.upstreamShortName.map { "\(branch.name) → \($0)" } ?? branch.name
        if let parent { name += "\nParent: \(parent)" }
        guard let worktree else { return name }
        let place = worktree.isMain ? "the main worktree" : "worktree \(worktree.folderName)"
        return "\(name)\nChecked out in \(place). Double-click to switch to it."
    }
}

/// Compact "↑2 ↓1" counts.
struct AheadBehindIndicator: View {

    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 4) {
            if ahead > 0 { Text("↑\(ahead)") }
            if behind > 0 { Text("↓\(behind)") }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }
}

#Preview {
    List {
        SidebarBranchRow(branch: MockData.branches[0])
        SidebarBranchRow(branch: MockData.branches[1], isPinned: true)
        SidebarBranchRow(branch: MockData.branches[2])
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 160)
}
