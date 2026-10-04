// ViewModels/SVNViewModel.swift
// GroveKit

import Foundation
import Observation

/// git-svn for one repository: in a Subversion-backed clone, Pull and Push become Fetch from and Commit to SVN.
@MainActor
@Observable
public final class SVNViewModel {

    public enum Sheet: String, Identifiable {
        case fetch, dcommit
        public var id: String { rawValue }
    }

    public let repository: any GitRepositoryProtocol
    public var onRepositoryChanged: (() async -> Void)?
    /// Reports each action this view model runs, e.g. to the app's telemetry.
    @ObservationIgnored public var onAction: GroveKitActionHandler?

    public private(set) var status = SVNStatus()
    public private(set) var sheet: Sheet?
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?

    public init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    public func refresh() async {
        status = await repository.svnStatus()
    }

    public func present(_ sheet: Sheet) {
        errorMessage = nil
        self.sheet = sheet
    }

    public func dismissSheet() {
        sheet = nil
        errorMessage = nil
    }

    public func fetch(rebase: Bool) async {
        await run { try await self.repository.svnFetch(rebase: rebase) }
    }

    public func dcommit() async {
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
            onAction?(.svn, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(.svn, false)
        }
        await refresh()
        await onRepositoryChanged?()
    }
}
