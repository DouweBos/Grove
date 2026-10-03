// Views/Stack/StackLayerCard.swift
// Grove

import GroveKit
import SwiftUI

/// One layer of the Stack tab: branch, PR and checks, its own commits and diff size, sync state and health.
struct StackLayerCard: View {

    let layer: StackLayer
    var stats: DiffStats?
    var commits: [CommitInfo]?
    var isExpanded = false
    var onToggle: () -> Void = {}
    var onCreatePullRequest: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if isExpanded { commitList }
        }
        .card(padding: Theme.Spacing.md)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .disabled(layer.commits.isEmpty)
            .help(isExpanded ? "Hide commits" : "Show this layer's commits")
            BranchLabel(name: layer.branch, kind: .localBranch(isHEAD: layer.isHEAD), maxNameWidth: 280)
            pullRequestBadge
            if let checks = layer.pullRequest?.checks, checks != .none {
                Image(systemName: checks.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(checks.color)
                    .help("Checks \(checks == .passing ? "passing" : checks == .failing ? "failing" : "running")")
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text("\(layer.commits.count) commit\(layer.commits.count == 1 ? "" : "s")")
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            if let stats {
                DiffStatsLabel(stats: stats)
                DiffStatsBar(stats: stats, width: 44)
            }
            if layer.ahead > 0 || layer.behind > 0 {
                AheadBehindIndicator(ahead: layer.ahead, behind: layer.behind)
                    .foregroundStyle(Theme.textSecondary)
            }
            markers
        }
    }

    @ViewBuilder
    private var pullRequestBadge: some View {
        if let pr = layer.pullRequest {
            StatusBadge(title: "\(pr.label) \(pr.isMerged ? "merged" : pr.isDraft ? "draft" : "review")",
                        symbol: pr.isMerged ? "arrow.merge" : "arrow.triangle.pull",
                        tone: pr.isMerged ? .positive : .neutral)
                .help(pr.tooltip)
        } else if layer.health.contains(.noPR) {
            StatusBadge(title: "No PR", symbol: "arrow.triangle.pull", tone: .neutral)
            if let onCreatePullRequest {
                Button("Create PR", action: onCreatePullRequest)
                    .controlSize(.small)
                    .help("Open a pull request based on \(layer.parent ?? "trunk")")
            }
        }
    }

    @ViewBuilder
    private var markers: some View {
        ForEach(LayerHealth.allCases.filter { layer.health.contains($0) && $0 != .noPR }, id: \.self) { health in
            StatusBadge(title: health.title, symbol: health.symbol,
                        tone: health == .unpushed ? .neutral : .caution)
        }
        if layer.isHEAD {
            StatusBadge(title: "HEAD", symbol: "location.fill", tone: .positive)
        }
        if let worktree = layer.worktreePath {
            Image(systemName: "tree.circle.fill")
                .foregroundStyle(Theme.info)
                .help("Checked out in worktree \(URL(fileURLWithPath: worktree).lastPathComponent)")
        }
    }

    @ViewBuilder
    private var commitList: some View {
        if let commits {
            VStack(spacing: 0) {
                ForEach(commits) { commit in
                    CommitRow(commit: commit)
                        .frame(height: CommitRow.height)
                }
            }
            .padding(.leading, 20)
        } else {
            ProgressView().controlSize(.small).padding(.leading, 20)
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.sm) {
        ForEach(MockData.linearStack.layers.reversed()) { layer in
            StackLayerCard(layer: layer, stats: DiffStats(additions: 140, deletions: 12),
                           commits: Array(MockData.commits.prefix(layer.commits.count)), isExpanded: layer.depth == 4)
        }
    }
    .padding()
    .frame(width: 900)
    .background(Theme.background)
}
