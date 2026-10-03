// ViewModels/SVNViewModel.swift
// GroveKit

import Foundation
import Observation

/// git-svn for one repository: in a Subversion-backed clone, Pull and Push become Fetch from and Commit to SVN.
@MainActor
@Observable
final class SVNViewModel {

    enum Sheet: String, Identifiable {
        case fetch, dcommit
        var id: String { rawValue }
    }

    let repository: any GitRepositoryProtocol
    var onRepositoryChanged: (() async -> Void)?

    private(set) var status = SVNStatus()
    private(set) var sheet: Sheet?
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    func refresh() async {
        status = await repository.svnStatus()
    }

    func present(_ sheet: Sheet) {
        errorMessage = nil
        self.sheet = sheet
    }

    func dismissSheet() {
        sheet = nil
        errorMessage = nil
    }

    func fetch(rebase: Bool) async {
        await run { try await self.repository.svnFetch(rebase: rebase) }
    }

    func dcommit() async {
        await run { try await self.repository.svnDcommit() }
    }

    /// Closes the sheet on success and keeps it with the error otherwise; a failed rebase still changed the tree.
    private func run(_ work: () async throws -> Void) async {
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            try await work()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
        await onRepositoryChanged?()
    }
}
