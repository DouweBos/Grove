// Views/History/InteractiveRebaseSheet.swift
// Grove

import SwiftUI

/// Plans an interactive rebase: an action per commit above `base`, reordered by drag.
struct InteractiveRebaseSheet: View {
    @Environment(HistoryViewModel.self) private var viewModel
    @State private var planner: InteractiveRebaseViewModel

    init(base: CommitInfo, commits: [CommitInfo]) {
        _planner = State(initialValue: InteractiveRebaseViewModel(base: base, commits: commits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HistorySheetHeader(symbol: "list.bullet.indent", title: "Interactive Rebase",
                               message: "Replays \(planner.steps.count) commit\(planner.steps.count == 1 ? "" : "s") onto "
                                   + "\(planner.base.shortSHA). Drag to reorder; squash and fixup fold into the commit below.")
            List {
                ForEach(planner.steps) { step in
                    RebaseStepRow(step: step, commit: planner.commit(for: step),
                                  onAction: { planner.setAction($0, for: step) },
                                  onMessage: { planner.setMessage($0, for: step) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: Theme.Spacing.xs, bottom: 2, trailing: Theme.Spacing.xs))
                }
                .onMove { planner.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(planner.steps.reduce(Theme.Spacing.md) { $0 + ($1.action == .reword ? 112 : 38) }, 400))
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            HStack(spacing: Theme.Spacing.sm) {
                Text(planner.summary).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            if let problem = planner.problem {
                Banner(symbol: "exclamationmark.triangle", message: problem, tone: .negative)
            } else if let warning = viewModel.pushedWarning(for: planner.steps.compactMap { planner.commit(for: $0) }) {
                Banner(symbol: "exclamationmark.triangle", message: warning, tone: .caution)
            }
            HistorySheetFooter(primaryTitle: "Start Rebase", isDisabled: planner.problem != nil || planner.isUnchanged) {
                await viewModel.rebaseInteractively(onto: planner.base, plan: planner.plan)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 620)
        .background(Theme.surface)
    }
}

/// One commit in the plan: drag handle, action menu, the commit, and a message editor for rewords.
private struct RebaseStepRow: View {
    let step: RebaseStep
    let commit: CommitInfo?
    let onAction: (RebaseAction) -> Void
    let onMessage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Picker("Action", selection: Binding(get: { step.action }, set: onAction)) {
                    ForEach(RebaseAction.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help(help(for: step.action))
                if step.action.foldsIntoPrevious {
                    Image(systemName: "arrow.turn.left.down")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Folds into the commit below")
                }
                Text(commit?.summary ?? step.sha)
                    .font(.rowTitle)
                    .strikethrough(step.action == .drop)
                    .foregroundStyle(step.action == .drop ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(commit?.shortSHA ?? String(step.sha.prefix(7)))
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if step.action == .reword {
                TextField("Commit message", text: Binding(get: { step.message ?? "" }, set: onMessage), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .lineLimit(1...4)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(Theme.surfaceRaised.opacity(step.action == .drop ? 0.4 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }

    private func help(for action: RebaseAction) -> String {
        switch action {
        case .pick: "Keep the commit as it is."
        case .reword: "Keep the changes and edit the message."
        case .squash: "Fold into the commit below, keeping both messages."
        case .fixup: "Fold into the commit below, discarding this message."
        case .drop: "Remove the commit and its changes."
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return InteractiveRebaseSheet(base: MockData.commits[4], commits: Array(MockData.commits.prefix(4)))
        .environment(vm)
}
