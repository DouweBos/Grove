// Views/WorkingCopy/WorkingCopyViewModel+AIDraft.swift
// Grove
//
// Drafting the commit message with Claude. Nothing leaves the Mac until the user clicks the button.

import Foundation

struct AIDraftState: Equatable {
    var isDrafting = false
    var errorMessage: String?
    /// Draft was clicked without a key; the composer explains how to add one.
    var needsKey = false
}

extension WorkingCopyViewModel {

    var hasAnthropicKey: Bool { loadAnthropicKey() != nil }

    var canDraftMessage: Bool { !stagedFiles.isEmpty && !aiDraft.isDrafting }

    /// Sends the staged diff to the Messages API and fills the summary and description.
    func draftCommitMessage() async {
        guard !aiDraft.isDrafting else { return }
        guard let key = loadAnthropicKey() else {
            aiDraft = AIDraftState(errorMessage: "Add an Anthropic API key in Preferences \u{203A} Accounts to draft messages.",
                                   needsKey: true)
            return
        }
        aiDraft = AIDraftState(isDrafting: true)
        do {
            let diff = try await repository.patch(paths: stagedFiles.map(\.path), staged: true)
            let draft = try await messageDrafter.draft(diff: diff, apiKey: key, branch: repository.currentBranch?.name)
            commitSubject = draft.summary
            commitBody = draft.description
            dismissAutoComplete()
            aiDraft = AIDraftState()
        } catch {
            aiDraft = AIDraftState(errorMessage: error.localizedDescription)
        }
    }

    func dismissDraftError() {
        aiDraft = AIDraftState()
    }
}
