// History/Sheets/GitInteractiveRebaseView.swift
// GroveUIKit
//
// Plans an interactive rebase of HEAD's commits above one: an action per commit, drag to reorder, new messages for rewords.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitInteractiveRebaseView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: HistoryViewModel
    private let from: String
    private let inSheet: Bool
    private let onClose: () -> Void
    @State private var planner: InteractiveRebaseViewModel?
    @State private var problem: String?

    /// - Parameters:
    ///   - from: The commit to replay onto, by SHA; it has to be on HEAD's first-parent line below HEAD.
    ///   - onClose: After Cancel, or once the rebase ran without stopping on a conflict.
    public init(viewModel: HistoryViewModel, from: String, onClose: @escaping () -> Void) {
        self.init(viewModel: viewModel, from: from, inSheet: false, onClose: onClose)
    }

    init(viewModel: HistoryViewModel, from: String, inSheet: Bool, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.from = from
        self.inSheet = inSheet
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if let planner {
                editor(planner)
            } else if let problem {
                GitEmptyState(systemImage: "list.bullet.indent", title: "Can't Rebase from Here", subtitle: problem,
                              actionTitle: "Close", action: onClose)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: inSheet ? 620 * style.fontScale : nil)
        .frame(minHeight: inSheet ? 240 : nil)
        .background(inSheet ? style.surface : .clear)
        .task(id: from) { await resolve() }
    }

    private func editor(_ planner: InteractiveRebaseViewModel) -> some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.lg) {
            HistorySheetHeader(symbol: "list.bullet.indent", title: "Interactive Rebase",
                               message: "Replays \(planner.steps.count) commit\(planner.steps.count == 1 ? "" : "s") onto "
                                   + "\(planner.base.shortSHA) \u{201C}\(planner.base.summary)\u{201D}. Newest first; drag to "
                                   + "reorder. Squash and fixup fold into the commit below.")
            List {
                ForEach(planner.steps) { step in
                    RebaseStepRow(step: step, commit: planner.commit(for: step),
                                  onAction: { planner.setAction($0, for: step) },
                                  onMessage: { planner.setMessage($0, for: step) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: GitMetrics.Spacing.xs, bottom: 2, trailing: GitMetrics.Spacing.xs))
                }
                .onMove { planner.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: inSheet ? min(listHeight(planner), 400) : nil)
            .frame(maxHeight: inSheet ? nil : .infinity)
            .background(style.background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
            Text(planner.summary).font(style.monoCaption).foregroundStyle(style.textSecondary)
            if let problem = planner.problem {
                GitBanner(symbol: "exclamationmark.triangle", message: problem, tone: .negative)
            } else if let warning = viewModel.pushedWarning(for: planner.steps.compactMap { planner.commit(for: $0) }) {
                GitBanner(symbol: "exclamationmark.triangle", message: warning, tone: .caution)
            }
            HistorySheetFooter(viewModel: viewModel, primaryTitle: "Start Rebase",
                               isDisabled: planner.problem != nil || planner.isUnchanged, cancel: onClose) {
                await start(planner)
            }
        }
        .padding(GitMetrics.Spacing.xl)
    }

    private func listHeight(_ planner: InteractiveRebaseViewModel) -> CGFloat {
        planner.steps.reduce(GitMetrics.Spacing.md) { $0 + ($1.action == .reword ? 112 : 38) * style.fontScale }
    }

    private func resolve() async {
        planner = nil
        problem = nil
        viewModel.dismissError()
        await viewModel.loadIfNeeded()
        // Candidates are read from the loaded log, so page the base in.
        if viewModel.commit(withID: from) == nil {
            guard await viewModel.contains(from) else {
                return problem = "Commit \(from.prefix(7)) isn't in \(viewModel.headBranchName ?? "HEAD")'s history."
            }
            await viewModel.selectCommit(id: from)
        }
        guard let base = viewModel.commit(withID: from) else {
            return problem = "Couldn't find commit \(from.prefix(7))."
        }
        guard let commits = viewModel.rebaseCandidates(onto: base), !commits.isEmpty else {
            return problem = "\(base.shortSHA) has to be on the checked-out branch's first-parent line, below HEAD, "
                + "with no merges above it."
        }
        planner = InteractiveRebaseViewModel(base: base, commits: commits)
    }

    private func start(_ planner: InteractiveRebaseViewModel) async {
        viewModel.dismissError()
        await viewModel.rebaseInteractively(onto: planner.base, plan: planner.plan)
        // A stopped rebase went to the conflicts through the view model.
        if viewModel.errorMessage == nil, viewModel.repository.repositoryState == .normal { onClose() }
    }
}

/// One commit in the plan: drag handle, action menu, the commit, and a message editor for rewords.
private struct RebaseStepRow: View {
    @Environment(\.gitStyle) private var style
    let step: RebaseStep
    let commit: CommitInfo?
    let onAction: (RebaseAction) -> Void
    let onMessage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Image(systemName: "line.3.horizontal").foregroundStyle(style.textSecondary).accessibilityHidden(true)
                Picker("Action", selection: Binding(get: { step.action }, set: onAction)) {
                    ForEach(RebaseAction.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .gitClickable()
                .help(help(for: step.action))
                .accessibilityLabel("Action for \(commit?.summary ?? step.sha)")
                if step.action.foldsIntoPrevious {
                    Image(systemName: "arrow.turn.left.down")
                        .foregroundStyle(style.textSecondary)
                        .accessibilityLabel("Folds into the commit below")
                }
                Text(commit?.summary ?? step.sha)
                    .font(style.font(13, .medium))
                    .strikethrough(step.action == .drop)
                    .foregroundStyle(step.action == .drop ? style.textSecondary : style.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GitMetrics.Spacing.sm)
                Text(commit?.shortSHA ?? String(step.sha.prefix(7))).font(style.monoCaption).foregroundStyle(style.textSecondary)
            }
            if step.action == .reword {
                TextField("Commit message", text: Binding(get: { step.message ?? "" }, set: onMessage), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(style.font(12))
                    .lineLimit(1...4)
                    .padding(.leading, 28)
                    .accessibilityLabel("New message")
            }
        }
        .padding(.vertical, GitMetrics.Spacing.xs)
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .background(style.surfaceRaised.opacity(step.action == .drop ? 0.4 : 1),
                    in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
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
#endif
