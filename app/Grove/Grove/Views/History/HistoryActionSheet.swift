// Views/History/HistoryActionSheet.swift
// Grove

import SwiftUI

/// Presents the sheet for whatever ``HistoryAction`` the view model has pending.
struct HistoryActionSheet: View {
    @Environment(HistoryViewModel.self) private var viewModel
    let action: HistoryAction

    var body: some View {
        switch action {
        case .createBranch(let commit):
            CreateBranchDialogView(repository: viewModel.repository,
                                   localBranches: viewModel.branches.filter(\.isLocal),
                                   fromRef: commit.id) { _ in Task { await viewModel.refCreated() } }
        case .createTag(let commit):
            CreateTagDialogView(repository: viewModel.repository, targetSHA: commit.id) { _ in
                Task { await viewModel.refCreated() }
            }
        case .revert(let commit):
            CommitActionSheet(commit: commit, symbol: "arrow.uturn.backward", title: "Revert Commit",
                              message: "Creates a new commit that undoes the changes made in this commit.",
                              primaryTitle: "Revert") { _ in await viewModel.revert(commit) }
        case .reset(let commit):
            ResetCommitSheet(commit: commit)
        case .reword(let commit):
            CommitActionSheet(commit: commit, symbol: "pencil", title: "Edit Commit Message",
                              message: rewriteNote(commit), initialText: commit.message,
                              primaryTitle: "Save Message") { await viewModel.reword(commit, message: $0) }
        case .squash(let commit):
            CommitActionSheet(commit: commit, symbol: "arrow.triangle.merge", title: "Squash with Parent",
                              message: "Combines this commit with its parent into one commit. " + rewriteNote(commit, ownCommits: 2),
                              initialText: viewModel.squashMessage(for: commit),
                              primaryTitle: "Squash") { await viewModel.squashWithParent(commit, message: $0) }
        case .drop(let commit):
            CommitActionSheet(commit: commit, symbol: "trash", title: "Delete Commit",
                              message: "Removes this commit and its changes from the branch. " + rewriteNote(commit),
                              primaryTitle: "Delete Commit", isDestructive: true) { _ in await viewModel.drop(commit) }
        case .fileHistory(let path):
            FileHistorySheet(repository: viewModel.repository, path: path, onRepositoryChanged: viewModel.onRepositoryChanged)
        case .compare(let branch):
            BranchComparisonSheet(repository: viewModel.repository, refs: viewModel.refs, target: branch, onRepositoryChanged: viewModel.onRepositoryChanged)
        }
    }

    /// `ownCommits` is how many commits the action itself replaces (squash replaces two).
    private func rewriteNote(_ commit: CommitInfo, ownCommits: Int = 1) -> String {
        let total = (viewModel.commits.firstIndex { $0.id == commit.id } ?? 0) + ownCommits
        return "Rewrites \(total) commit\(total == 1 ? "" : "s"); avoid this on commits you've already pushed."
    }
}

/// Shared layout for confirm-style sheets: icon, title, the commit, optional message editor, buttons.
struct CommitActionSheet: View {
    @Environment(HistoryViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let commit: CommitInfo
    let symbol: String
    let title: String
    let message: String
    var initialText: String?
    let primaryTitle: String
    var isDestructive = false
    let perform: (String) async -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HistorySheetHeader(symbol: symbol, title: title, message: message, isDestructive: isDestructive)
            CommitSummaryTile(commit: commit)
            if initialText != nil {
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: 120)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.border, lineWidth: 0.5))
            }
            HistorySheetFooter(primaryTitle: primaryTitle, isDestructive: isDestructive,
                               isDisabled: initialText != nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                await perform(text)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
        .background(Theme.surface)
        .onAppear { text = initialText ?? "" }
    }
}

/// Reset HEAD with a soft / mixed / hard choice; hard asks once more because it discards work.
struct ResetCommitSheet: View {
    @Environment(HistoryViewModel.self) private var viewModel
    let commit: CommitInfo

    @State private var mode: ResetMode = .mixed
    @State private var isConfirmingHard = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HistorySheetHeader(symbol: "arrow.counterclockwise", title: "Reset HEAD",
                               message: "Moves \(viewModel.headBranchName ?? "HEAD") to this commit.",
                               isDestructive: mode == .hard)
            CommitSummaryTile(commit: commit)
            Picker("Mode", selection: $mode) {
                modeOption(.soft, "Soft", "Keep all changes staged.")
                modeOption(.mixed, "Mixed", "Keep changes in the working copy, unstaged.")
                modeOption(.hard, "Hard", "Discard all changes after this commit.")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if mode == .hard {
                Banner(symbol: "exclamationmark.triangle", message: "Uncommitted changes and later commits will be lost.", tone: .negative)
            }
            HistorySheetFooter(primaryTitle: mode == .hard ? "Reset and Discard" : "Reset",
                               isDestructive: mode == .hard) {
                if mode == .hard { isConfirmingHard = true } else { await viewModel.reset(to: commit, mode: mode) }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
        .background(Theme.surface)
        .confirmationDialog("Discard all changes after \(commit.shortSHA)?", isPresented: $isConfirmingHard) {
            Button("Reset and Discard", role: .destructive) { Task { await viewModel.reset(to: commit, mode: .hard) } }
        } message: {
            Text("This can't be undone from Grove.")
        }
    }

    private func modeOption(_ mode: ResetMode, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.rowTitle)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .tag(mode)
    }
}
