// Views/History/HistorySheetComponents.swift
// Grove

import SwiftUI

struct HistorySheetHeader: View {
    let symbol: String
    let title: String
    let message: String
    var isDestructive = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            let tint = isDestructive ? Theme.danger : Theme.accent
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The commit an action applies to, as a small tile.
struct CommitSummaryTile: View {
    let commit: CommitInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AvatarView(name: commit.authorName, email: commit.authorEmail, size: .small)
            Text(commit.summary).font(.rowTitle).lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            Text(commit.shortSHA).font(.monoCaption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }
}

/// Error line plus Cancel / primary buttons, wired to the view model's action state.
struct HistorySheetFooter: View {
    @Environment(HistoryViewModel.self) private var viewModel
    let primaryTitle: String
    var isDestructive = false
    var isDisabled = false
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let error = viewModel.errorMessage {
                Banner(symbol: "xmark.octagon", message: error, tone: .negative)
            }
            HStack {
                if viewModel.isPerformingAction { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { viewModel.dismissAction() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { Task { await action() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(isDestructive ? Theme.danger : Theme.accent)
                    .disabled(isDisabled || viewModel.isPerformingAction)
            }
        }
    }
}

/// Sheet chrome for the larger tools (file history, branch comparison).
struct HistoryToolSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var detail: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let detail {
                    Text(detail).font(.monoCaption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            content()
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 540, idealHeight: 640)
        .background(Theme.background)
    }
}

struct FileHistorySheet: View {
    @State private var viewModel: FileHistoryViewModel

    init(repository: any GitRepositoryProtocol, path: String, onRepositoryChanged: (() async -> Void)? = nil) {
        let viewModel = FileHistoryViewModel(repository: repository, filePath: path)
        viewModel.onRepositoryChanged = onRepositoryChanged
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HistoryToolSheet(title: "File History", detail: viewModel.filePath) {
            FileHistoryView().environment(viewModel)
        }
    }
}

struct BranchComparisonSheet: View {
    let repository: any GitRepositoryProtocol
    var refs: RepositoryRefs?
    let target: BranchInfo
    var onRepositoryChanged: (() async -> Void)?

    var body: some View {
        HistoryToolSheet(title: "Compare Branches") {
            BranchComparisonView(repository: repository, refs: refs, initialTarget: target, onRepositoryChanged: onRepositoryChanged)
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitActionSheet(commits: [MockData.commits[0]], symbol: "arrow.uturn.backward", title: "Revert Commit",
                             message: "Creates a new commit that undoes the changes made in this commit.",
                             primaryTitle: "Revert") { _ in }
        .environment(vm)
}
