// Views/Stack/StackView.swift
// Grove
//
// The Stack tab: the stack HEAD or the sidebar's branch belongs to, tips on top and trunk at the bottom.

import SwiftUI

struct StackView: View {

    @Environment(StackViewModel.self) private var viewModel
    @State private var newBranchFrom: CreateBranchRequest?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let stack = viewModel.stack {
                header(stack)
                if let activity = viewModel.activity {
                    ProgressStrip(title: activity, detail: "", fraction: nil)
                }
                ForEach(viewModel.mergedParents(stack)) { merged in
                    Banner(symbol: "arrow.merge", message: retargetMessage(merged, trunk: stack.trunk), tone: .positive,
                           actionTitle: "Retarget", action: { Task { await viewModel.retarget(merged) } })
                        .disabled(viewModel.isBusy)
                }
                if let merged = viewModel.retargetedParent {
                    Banner(symbol: "trash", message: "Retargeted. Delete the merged branch \(merged)?", tone: .caution,
                           actionTitle: "Delete \(merged)", action: { Task { await viewModel.deleteMergedParent() } },
                           onDismiss: { viewModel.keepMergedParent() })
                }
                if let message = viewModel.errorMessage {
                    Banner(symbol: "xmark.octagon", message: message, tone: .negative) { viewModel.dismissError() }
                }
                ScrollView {
                    StackTree(stack: stack) { newBranchFrom = CreateBranchRequest(ref: $0.branch) }
                        .padding(.bottom, Theme.Spacing.lg)
                }
            } else {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "No Stacks",
                               subtitle: "Branches built on other unmerged branches show up here as a stack.")
            }
        }
        .padding(.bottom, Theme.Spacing.md)
        .task(id: viewModel.stack) { await viewModel.refresh() }
        .sheet(item: $newBranchFrom) { request in
            CreateBranchDialogView(repository: viewModel.repository, localBranches: viewModel.refs.localBranches,
                                   fromRef: request.ref) { _ in
                Task { await viewModel.onRepositoryChanged?() }
            }
        }
    }

    private func header(_ stack: BranchStack) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(stack.needsAttention ? Theme.warning : Theme.textSecondary)
            if viewModel.stacks.count > 1 {
                StackTitleButton(title: stack.name)
            } else {
                Text(stack.name).font(.pageTitle)
            }
            Text(summary(stack))
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await viewModel.sync() } }
                .help("Fetch, then restack every layer onto \(stack.trunk)'s new tip")
            Button("Restack", systemImage: "square.stack.3d.up") { Task { await viewModel.restackDrifted() } }
                .disabled(!viewModel.canRestack(stack))
                .help("Move only the layers that drifted from their parent, and what sits on them")
            Button("Push Stack", systemImage: "arrow.up") { Task { await viewModel.pushStack() } }
                .disabled(viewModel.changedLayers(stack).isEmpty)
                .help("Push every changed layer at once, each only if its remote branch hasn't moved")
        }
        .disabled(viewModel.isBusy)
        .card(padding: Theme.Spacing.md)
    }

    private func retargetMessage(_ merged: MergedParent, trunk: String) -> String {
        let children = merged.children.map(\.branch).joined(separator: ", ")
        let pr = merged.pullRequest.map { " (\($0.label))" } ?? ""
        return "\(merged.branch)\(pr) merged into \(trunk). Retarget \(children) onto \(trunk)? "
            + "Grove rebases, pushes what's already on the remote, and points the pull requests at \(trunk)."
    }

    private func summary(_ stack: BranchStack) -> String {
        let layers = "\(stack.layers.count) layer\(stack.layers.count == 1 ? "" : "s")"
        let behind = stack.trunkAhead > 0 ? ", \(stack.trunkAhead) behind" : ""
        return "\(layers) \u{00B7} trunk \(stack.trunk)\(behind)"
    }
}

/// The stack's name; clicking it opens the stack switcher, like the sidebar's repository title.
private struct StackTitleButton: View {
    @Environment(StackViewModel.self) private var viewModel
    let title: String
    @State private var isShowingSwitcher = false

    var body: some View {
        Button { isShowingSwitcher = true } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.pageTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Switch Stack")
        .popover(isPresented: $isShowingSwitcher, arrowEdge: .bottom) {
            StackSwitcher { isShowingSwitcher = false }
                .environment(viewModel)
        }
    }
}

/// Layer cards with lane connectors, then the trunk row.
private struct StackTree: View {
    @Environment(StackViewModel.self) private var viewModel
    let stack: BranchStack
    let onNewBranch: (StackLayer) -> Void

    var body: some View {
        let layout = StackTreeLayout(stack)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(layout.rows) { row in
                if let layer = stack.layer(row.branch) {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        StackLaneGutter(segments: row.segments, lane: row.lane, laneCount: layout.laneCount, isHEAD: layer.isHEAD)
                        StackLayerCard(layer: layer, stats: viewModel.stats(for: layer), commits: viewModel.commits(for: layer),
                                       isExpanded: viewModel.expandedLayers.contains(layer.branch),
                                       onToggle: { viewModel.toggleExpanded(layer) },
                                       onCreatePullRequest: { viewModel.createPullRequest(for: layer) })
                        .padding(.bottom, Theme.Spacing.sm)
                        .contextMenu { StackLayerMenu(layer: layer, onNewBranch: onNewBranch) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                StackLaneGutter(segments: layout.trunkLanes.map { .top($0) }, lane: nil, laneCount: layout.laneCount)
                    .frame(height: StackLaneGutter.nodeY)
                HStack(spacing: Theme.Spacing.sm) {
                    BranchLabel(name: stack.trunk, kind: .localBranch(isHEAD: false))
                    if stack.trunkAhead > 0 {
                        Text("\(stack.trunkAhead) new commit\(stack.trunkAhead == 1 ? "" : "s") since the stack's base")
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, StackLaneGutter.nodeY - 10)
            }
        }
    }
}

#Preview("Linear") {
    let refs = RepositoryRefs(repository: MockGitRepository())
    refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.linearStack, MockData.splitStack])
    return StackView()
        .environment(StackViewModel(repository: MockGitRepository(), refs: refs))
        .padding()
        .frame(width: 1000, height: 600)
        .background(Theme.background)
}

#Preview("Split") {
    let refs = RepositoryRefs(repository: MockGitRepository())
    refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.splitStack])
    return StackView()
        .environment(StackViewModel(repository: MockGitRepository(), refs: refs))
        .padding()
        .frame(width: 1000, height: 500)
        .background(Theme.background)
}
