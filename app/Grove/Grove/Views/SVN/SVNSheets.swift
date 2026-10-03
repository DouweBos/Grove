// Views/SVN/SVNSheets.swift
// Grove
//
// Fetch from SVN and Commit to SVN, shown in place of Pull and Push for git-svn clones.

import GroveKit
import SwiftUI

struct SVNSheetView: View {
    let viewModel: SVNViewModel
    let sheet: SVNViewModel.Sheet

    var body: some View {
        switch sheet {
        case .fetch: SVNFetchSheet(viewModel: viewModel)
        case .dcommit: SVNDcommitSheet(viewModel: viewModel)
        }
    }
}

struct SVNFetchSheet: View {
    let viewModel: SVNViewModel
    @State private var rebase = true

    var body: some View {
        DialogSheet(
            title: "Fetch from SVN",
            message: "Downloads new revisions from \(viewModel.status.url ?? "the Subversion repository").",
            symbol: "arrow.down.to.line",
            progress: viewModel.isRunning ? (rebase ? "Fetching and rebasing…" : "Fetching revisions…") : nil,
            errorMessage: viewModel.errorMessage ?? (viewModel.status.isAvailable ? nil : SVNStatus.missingMessage),
            primaryTitle: rebase ? "Fetch and Rebase" : "Fetch",
            isPrimaryDisabled: !viewModel.status.isAvailable,
            onCancel: viewModel.dismissSheet,
            onPrimary: fetch
        ) {
            DialogCard {
                Picker("After fetching", selection: $rebase) {
                    Text("Rebase local commits onto the new revisions").tag(true)
                    Text("Only fetch").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(rebase ? "git svn rebase: like pull with rebase, your unsent commits are replayed on top."
                     : "git svn fetch: updates the SVN branches without touching your working copy.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fetch() {
        Task { await viewModel.fetch(rebase: rebase) }
    }
}

struct SVNDcommitSheet: View {
    let viewModel: SVNViewModel

    private var unsent: Int { viewModel.status.unsentCount }

    var body: some View {
        DialogSheet(
            title: "Commit to SVN",
            message: "Sends \(unsent == 1 ? "1 local commit" : "\(unsent) local commits") to \(viewModel.status.url ?? "Subversion"), "
                + "one revision each. They're then rewritten with their SVN revision, so their hashes change.",
            symbol: "arrow.up.to.line",
            progress: viewModel.isRunning ? "Committing to SVN…" : nil,
            errorMessage: viewModel.errorMessage ?? (viewModel.status.isAvailable ? nil : SVNStatus.missingMessage),
            primaryTitle: "Commit to SVN",
            isPrimaryDisabled: !viewModel.status.isAvailable || unsent < 1,
            onCancel: viewModel.dismissSheet,
            onPrimary: dcommit
        ) {
            DialogCard {
                DialogField("Destination") {
                    Text(viewModel.status.url ?? "Unknown").font(.monoCaption).lineLimit(1).truncationMode(.middle)
                }
                DialogField("Commits") {
                    Text(unsent < 1 ? "Nothing to send" : "\(unsent)").font(.monoCaption)
                }
            }
        }
    }

    private func dcommit() {
        Task { await viewModel.dcommit() }
    }
}

#Preview {
    SVNFetchSheet(viewModel: SVNViewModel(repository: MockGitRepository()))
}
