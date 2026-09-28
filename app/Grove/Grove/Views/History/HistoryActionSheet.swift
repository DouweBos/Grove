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
            CommitActionSheet(commits: [commit], symbol: "arrow.uturn.backward", title: "Revert Commit",
                              message: "Creates a new commit that undoes the changes made in this commit.",
                              primaryTitle: "Revert") { _ in await viewModel.revert(commit) }
        case .reset(let commit):
            ResetCommitSheet(commit: commit)
        case .reword(let commit):
            CommitActionSheet(commits: [commit], symbol: "pencil", title: "Edit Commit Message",
                              message: rewriteNote(from: commit), warning: pushedWarning(from: commit),
                              initialText: commit.message,
                              primaryTitle: "Save Message") { await viewModel.reword(commit, message: $0) }
        case .squash(let commit):
            let parent = commit.parentIDs.first.flatMap { viewModel.commit(withID: $0) } ?? commit
            CommitActionSheet(commits: [commit], symbol: "arrow.triangle.merge", title: "Squash with Parent",
                              message: "Combines this commit with its parent into one commit. " + rewriteNote(from: parent),
                              warning: pushedWarning(from: parent), initialText: viewModel.squashMessage(for: commit),
                              primaryTitle: "Squash") { await viewModel.squashWithParent(commit, message: $0) }
        case .squashCommits(let commits):
            let oldest = commits.last ?? commits[0]
            CommitActionSheet(commits: commits, symbol: "arrow.triangle.merge", title: "Squash \(commits.count) Commits",
                              message: "Combines these commits into one commit. " + rewriteNote(from: oldest),
                              warning: pushedWarning(from: oldest), initialText: viewModel.squashMessage(for: commits),
                              primaryTitle: "Squash") { await viewModel.squash(commits, message: $0) }
        case .drop(let commit):
            CommitActionSheet(commits: [commit], symbol: "trash", title: "Delete Commit",
                              message: "Removes this commit and its changes from the branch. " + rewriteNote(from: commit),
                              warning: pushedWarning(from: commit),
                              primaryTitle: "Delete Commit", isDestructive: true) { _ in await viewModel.drop(commit) }
        case .fileHistory(let path):
            FileHistorySheet(repository: viewModel.repository, path: path)
        case .compare(let branch):
            BranchComparisonSheet(repository: viewModel.repository, refs: viewModel.refs, target: branch, onRepositoryChanged: viewModel.onRepositoryChanged)
        }
    }

    /// A rewrite from `oldest` replaces it and every commit above it.
    private func rewriteNote(from oldest: CommitInfo) -> String {
        let total = viewModel.rewrittenCount(from: oldest)
        return "Rewrites \(total) commit\(total == 1 ? "" : "s"); avoid this on commits you've already pushed."
    }

    private func pushedWarning(from oldest: CommitInfo) -> String? {
        let rewritten = viewModel.firstParentLine(reaching: [oldest.id]).compactMap { viewModel.commit(withID: $0) }
        let pushed = viewModel.pushedCommits(in: rewritten).count
        guard pushed > 0 else { return nil }
        return "\(pushed) of these commit\(pushed == 1 ? " is" : "s are") already on \(viewModel.upstreamName ?? "the upstream"); "
            + "pushing afterwards needs a force push."
    }
}

/// Shared layout for confirm-style sheets: icon, title, the commit, optional message editor, buttons.
struct CommitActionSheet: View {
    @Environment(HistoryViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HistorySheetHeader(symbol: symbol, title: title, message: message, isDestructive: isDestructive)
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(commits.prefix(Self.tileLimit)) { CommitSummaryTile(commit: $0) }
                if commits.count > Self.tileLimit {
                    Text("and \(commits.count - Self.tileLimit) more").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if let warning {
                Banner(symbol: "exclamationmark.triangle", message: warning, tone: .caution)
            }
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
