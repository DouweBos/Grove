// Views/History/CommitContextMenu.swift
// Grove

import AppKit
import SwiftUI

/// Right-click menu for a commit row.
struct CommitContextMenu: View {
    @Environment(HistoryViewModel.self) private var viewModel
    let commit: CommitInfo

    var body: some View {
        Button("Copy Commit SHA") { copy(commit.id) }
        Button("Copy Short SHA") { copy(commit.shortSHA) }
        Button("Copy Commit Message") { copy(commit.message) }
        Divider()
        Button("Create Branch from \u{201C}\(commit.shortSHA)\u{201D}\u{2026}") { viewModel.request(.createBranch(commit)) }
        Button("Create Tag at \u{201C}\(commit.shortSHA)\u{201D}\u{2026}") { viewModel.request(.createTag(commit)) }
        let comparable = viewModel.branches(at: commit).filter { !$0.isHEAD }
        if !comparable.isEmpty {
            Menu("Compare with HEAD") {
                ForEach(comparable) { branch in
                    Button(branch.name) { viewModel.request(.compare(branch)) }
                }
            }
        }
        Divider()
        Button("Cherry-Pick \u{201C}\(commit.shortSHA)\u{201D}") { Task { await viewModel.cherryPick(commit) } }
            .disabled(commit.id == viewModel.headSHA)
        Button("Revert \u{201C}\(commit.shortSHA)\u{201D}\u{2026}") { viewModel.request(.revert(commit)) }
        Divider()
        Button("Reset HEAD to \u{201C}\(commit.shortSHA)\u{201D}\u{2026}") { viewModel.request(.reset(commit)) }
            .disabled(viewModel.filterBranch != nil)
        Divider()
        Button("Edit Commit Message\u{2026}") { viewModel.request(.reword(commit)) }
            .disabled(!viewModel.canRewrite(commit))
        Button("Squash with Parent\u{2026}") { viewModel.request(.squash(commit)) }
            .disabled(!viewModel.canSquashWithParent(commit))
        Button("Delete \u{201C}\(commit.shortSHA)\u{201D}\u{2026}", role: .destructive) { viewModel.request(.drop(commit)) }
            .disabled(!viewModel.canRewrite(commit))
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
