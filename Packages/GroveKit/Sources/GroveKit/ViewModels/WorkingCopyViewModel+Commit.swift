// ViewModels/WorkingCopyViewModel+Commit.swift
// GroveKit
//
// Commit composer options and the commit itself.

import Foundation

extension WorkingCopyViewModel {

    public func setAmend(_ on: Bool) async {
        isAmend = on
        if on {
            guard !hasSubject, commitBody.isEmpty,
                  let head = try? await repository.commitDetail("HEAD") else { return }
            let body = head.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            commitSubject = head.summary
            commitBody = body
            amendPrefill = (head.summary, body)
            dismissAutoComplete()
        } else if let prefill = amendPrefill {
            if commitSubject == prefill.subject && commitBody == prefill.body {
                commitSubject = ""
                commitBody = ""
            }
            amendPrefill = nil
        }
    }

    public func setSignOff(_ on: Bool) {
        signOff = on
    }

    public func setSignCommit(_ on: Bool) {
        signCommit = on
    }

    public func commit() async {
        guard canCommit else {
            if !hasSubject { errorMessage = "Please enter a commit subject." }
            return
        }
        isCommitting = true
        defer { isCommitting = false }
        do {
            let message = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmedBody.isEmpty ? nil : trimmedBody
            // No previous HEAD means the first commit, which a soft reset can't undo.
            let previousHead = try? await repository.commitDetail("HEAD").id
            let (repo, amend, sign, signOff) = (repository, isAmend, signCommit, signOff)
            let commit: @MainActor () async throws -> Void = {
                try await repo.commit(message: message, body: body, amend: amend, sign: sign, signOff: signOff)
            }
            try await commit()
            if let previousHead {
                undoManager?.record(GitUndoManager.commitAction(amend: amend, previousHead: previousHead,
                                                                repository: repo, recommit: commit))
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        commitSubject = ""
        commitBody = ""
        isAmend = false
        amendPrefill = nil
        dismissAutoComplete()
        didPrefillGitTemplate = false
        prefillGitTemplateIfNeeded()
        await repositoryChanged()
    }
}
