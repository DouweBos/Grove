// History/Sheets/HistoryActionSheet.swift
// GroveUIKit
//
// The sheet for whatever HistoryAction the view model has pending.

#if os(macOS)
import GroveKit
import SwiftUI

struct HistoryActionSheet: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let dialogs: GitDialogContext
    let action: HistoryAction

    var body: some View {
        switch action {
        case .createBranch(let commit):
            GitDialogView(.createBranch(from: commit.id), context: dialogs)
        case .createTag(let commit):
            GitDialogView(.createTag(at: commit.id), context: dialogs)
        case .revert(let commit):
            CommitActionSheet(viewModel: viewModel, commits: [commit], symbol: "arrow.uturn.backward", title: "Revert Commit",
                              message: "Creates a new commit that undoes the changes made in this commit.",
                              primaryTitle: "Revert") { _ in await viewModel.revert(commit) }
        case .reset(let commit):
            ResetCommitSheet(viewModel: viewModel, commit: commit)
        case .reword(let commit):
            CommitActionSheet(viewModel: viewModel, commits: [commit], symbol: "pencil", title: "Edit Commit Message",
                              message: rewriteNote(from: commit), warning: pushedWarning(from: commit),
                              initialText: commit.message,
                              primaryTitle: "Save Message") { await viewModel.reword(commit, message: $0) }
        case .squash(let commit):
            let parent = commit.parentIDs.first.flatMap { viewModel.commit(withID: $0) } ?? commit
            CommitActionSheet(viewModel: viewModel, commits: [commit], symbol: "arrow.triangle.merge", title: "Squash with Parent",
                              message: "Combines this commit with its parent into one commit. " + rewriteNote(from: parent),
                              warning: pushedWarning(from: parent), initialText: viewModel.squashMessage(for: commit),
                              primaryTitle: "Squash") { await viewModel.squashWithParent(commit, message: $0) }
        case .squashCommits(let commits):
            let oldest = commits.last ?? commits[0]
            CommitActionSheet(viewModel: viewModel, commits: commits, symbol: "arrow.triangle.merge",
                              title: "Squash \(commits.count) Commits",
                              message: "Combines these commits into one commit. " + rewriteNote(from: oldest),
                              warning: pushedWarning(from: oldest), initialText: viewModel.squashMessage(for: commits),
                              primaryTitle: "Squash") { await viewModel.squash(commits, message: $0) }
        case .interactiveRebase(let base):
            GitInteractiveRebaseView(viewModel: viewModel, from: base.id, inSheet: true) { viewModel.dismissAction() }
        case .drop(let commit):
            CommitActionSheet(viewModel: viewModel, commits: [commit], symbol: "trash", title: "Delete Commit",
                              message: "Removes this commit and its changes from the branch. " + rewriteNote(from: commit),
                              warning: pushedWarning(from: commit), primaryTitle: "Delete Commit",
                              isDestructive: true) { _ in await viewModel.drop(commit) }
        case .fileHistory(let path):
            FileHistorySheet(history: viewModel, path: path)
        case .compare(let branch):
            HistoryToolSheet(title: "Compare Branches", done: { viewModel.dismissAction() }) {
                CompareSheetContent(context: dialogs, base: viewModel.headBranchName ?? "HEAD", compare: branch.name)
            }
        }
    }

    /// A rewrite from `oldest` replaces it and every commit above it.
    private func rewriteNote(from oldest: CommitInfo) -> String {
        let total = viewModel.rewrittenCount(from: oldest)
        return "Rewrites \(total) commit\(total == 1 ? "" : "s"); avoid this on commits you've already pushed."
    }

    private func pushedWarning(from oldest: CommitInfo) -> String? {
        viewModel.pushedWarning(for: viewModel.firstParentLine(reaching: [oldest.id]).compactMap { viewModel.commit(withID: $0) })
    }
}

/// Confirm-style sheet: icon, title, the commits, an optional message editor, buttons.
struct CommitActionSheet: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let commits: [CommitInfo]
    let symbol: String
    let title: String
    let message: String
    var warning: String?
    var initialText: String?
    let primaryTitle: String
    var isDestructive = false
    let perform: (String) async -> Void

    @State private var text = ""
    private static let tileLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.lg) {
            HistorySheetHeader(symbol: symbol, title: title, message: message, isDestructive: isDestructive)
            VStack(spacing: GitMetrics.Spacing.xs) {
                ForEach(commits.prefix(Self.tileLimit)) { CommitSummaryTile(commit: $0) }
                if commits.count > Self.tileLimit {
                    Text("and \(commits.count - Self.tileLimit) more").font(style.monoCaption).foregroundStyle(style.textSecondary)
                }
            }
            if let warning {
                GitBanner(symbol: "exclamationmark.triangle", message: warning, tone: .caution)
            }
            if initialText != nil {
                TextEditor(text: $text)
                    .font(style.font(13))
                    .scrollContentBackground(.hidden)
                    .padding(GitMetrics.Spacing.sm)
                    .frame(height: 120 * style.fontScale)
                    .background(style.background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
                    .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.tile).strokeBorder(style.border, lineWidth: 0.5))
                    .accessibilityLabel("Commit message")
            }
            HistorySheetFooter(viewModel: viewModel, primaryTitle: primaryTitle, isDestructive: isDestructive,
                               isDisabled: initialText != nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                await perform(text)
            }
        }
        .padding(GitMetrics.Spacing.xl)
        .frame(width: 480 * style.fontScale)
        .background(style.surface)
        .onAppear { text = initialText ?? "" }
    }
}

/// Reset HEAD soft, mixed or hard; hard asks once more because it discards work.
struct ResetCommitSheet: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let commit: CommitInfo

    @State private var mode: ResetMode = .mixed
    @State private var isConfirmingHard = false

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.lg) {
            HistorySheetHeader(symbol: "arrow.counterclockwise", title: "Reset \(viewModel.headBranchName ?? "HEAD")",
                               message: "Moves \(viewModel.headBranchName ?? "HEAD") to this commit.", isDestructive: mode == .hard)
            CommitSummaryTile(commit: commit)
            Picker("Mode", selection: $mode) {
                option(.soft, "Soft", "Keep all changes staged.")
                option(.mixed, "Mixed", "Keep changes in the working copy, unstaged.")
                option(.hard, "Hard", "Discard all changes after this commit.")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if mode == .hard {
                GitBanner(symbol: "exclamationmark.triangle", message: "Uncommitted changes and later commits will be lost.",
                          tone: .negative)
            }
            HistorySheetFooter(viewModel: viewModel, primaryTitle: mode == .hard ? "Reset and Discard" : "Reset",
                               isDestructive: mode == .hard) {
                if mode == .hard { isConfirmingHard = true } else { await viewModel.reset(to: commit, mode: mode) }
            }
        }
        .padding(GitMetrics.Spacing.xl)
        .frame(width: 480 * style.fontScale)
        .background(style.surface)
        .confirmationDialog("Discard all changes after \(commit.shortSHA)?", isPresented: $isConfirmingHard) {
            Button("Reset and Discard", role: .destructive) { Task { await viewModel.reset(to: commit, mode: .hard) } }
        } message: {
            Text("Uncommitted work can't be recovered.")
        }
    }

    private func option(_ mode: ResetMode, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(style.font(13, .medium))
            Text(detail).font(style.font(12)).foregroundStyle(style.textSecondary)
        }
        .padding(.vertical, 2)
        .tag(mode)
    }
}
#endif
