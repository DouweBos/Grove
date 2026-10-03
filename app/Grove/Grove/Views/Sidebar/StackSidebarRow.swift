// Views/Sidebar/StackSidebarRow.swift
// Grove

import GroveKit
import SwiftUI

/// One layer of a stack: its name indented by depth, PR label, health glyphs and ahead/behind.
struct StackSidebarRow: View {

    let layer: StackLayer
    let branch: BranchInfo
    /// Another worktree that has this branch checked out.
    var worktree: WorktreeInfo?

    /// Health worth a glyph in a narrow row; the rest shows in the tooltip and the Stack tab.
    private static let shownHealth: [LayerHealth] = [.parentMerged, .needsRestack, .unpushed]

    private var displayName: String { layer.branch.split(separator: "/").last.map(String.init) ?? layer.branch }

    var body: some View {
        SidebarRow(
            title: displayName,
            symbol: branch.isHEAD ? "checkmark.circle.fill" : "arrow.triangle.branch",
            tint: branch.isHEAD ? Theme.accent : Theme.textSecondary,
            detail: layer.pullRequest?.label,
            isEmphasized: branch.isHEAD,
            badgeSymbol: worktree == nil ? nil : "tree.circle.fill"
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Self.shownHealth.filter(layer.health.contains), id: \.self) { health in
                    Image(systemName: health.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(health == .unpushed ? Theme.textSecondary : Theme.warning)
                }
                if branch.ahead > 0 || branch.behind > 0 {
                    AheadBehindIndicator(ahead: branch.ahead, behind: branch.behind)
                }
            }
        }
        .padding(.leading, CGFloat(layer.depth) * 12)
        .help(tooltip)
    }

    private var tooltip: String {
        var lines = [branch.name, "On \(layer.parent ?? "trunk") \u{00B7} \(layer.commits.count) commit\(layer.commits.count == 1 ? "" : "s")"]
        if let pullRequest = layer.pullRequest { lines.append(pullRequest.tooltip) }
        lines += LayerHealth.allCases.filter(layer.health.contains).map(\.title)
        if let worktree { lines.append("Checked out in worktree \(worktree.folderName).") }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    List {
        ForEach(MockData.linearStack.layers) { layer in
            StackSidebarRow(layer: layer, branch: MockData.stackBranches.first { $0.name == layer.branch }!)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 200)
}
