// Views/GitFlow/GitFlowViewModel.swift
// Grove

import Foundation
import Observation

/// Which git-flow sheet is up; the toolbar menu and sidebar both open them.
enum GitFlowSheet: Identifiable, Equatable {
    case initialize
    case start(GitFlowKind)
    /// `name` preselects a branch, e.g. from the branch's context menu.
    case finish(GitFlowKind, name: String?)

    var id: String {
        switch self {
        case .initialize: "initialize"
        case .start(let kind): "start-\(kind.rawValue)"
        case .finish(let kind, let name): "finish-\(kind.rawValue)-\(name ?? "")"
        }
    }
}

/// git-flow for one repository: whether it's set up, and starting and finishing its branches.
@MainActor
@Observable
final class GitFlowViewModel {

    let repository: any GitRepositoryProtocol
    /// Shared with the session so the sheets list branches without reading them again.
    let refs: RepositoryRefs
    var onRepositoryChanged: (() async -> Void)?

    private(set) var config: GitFlowConfig?
    private(set) var sheet: GitFlowSheet?
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    var isInitialized: Bool { config != nil }

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs) {
        self.repository = repository
        self.refs = refs
    }

    func refresh() async {
        config = await repository.gitFlowConfig()
    }

    // MARK: Sheets

    func present(_ sheet: GitFlowSheet) {
        errorMessage = nil
        self.sheet = sheet
    }

    func dismissSheet() {
        sheet = nil
        errorMessage = nil
    }

    // MARK: Branches

    /// Existing branches of `kind`, by their short name.
    func branchNames(of kind: GitFlowKind) -> [String] {
        guard let config else { return [] }
        return refs.localBranches.compactMap { branch in
            config.classify(branch: branch.name).flatMap { $0.kind == kind ? $0.name : nil }
        }
    }

    /// The flow branch checked out now, if any, so Finish can offer it first.
    var currentFlowBranch: (kind: GitFlowKind, name: String)? {
        guard let head = refs.localBranches.first(where: \.isHEAD) else { return nil }
        return config?.classify(branch: head.name)
    }

    /// git-flow's defaults, with production set to whichever of main or master exists.
    var suggestedConfig: GitFlowConfig {
        var config = GitFlowConfig()
        let names = Set(refs.localBranches.map(\.name))
        if !names.contains("main"), names.contains("master") { config.productionBranch = "master" }
        return config
    }

    // MARK: Actions

    func initialize(_ config: GitFlowConfig) async {
        await run { try await self.repository.initializeGitFlow(config) }
    }

    func start(_ kind: GitFlowKind, name: String, base: String?) async {
        guard let config else { return errorMessage = GitFlowError.notInitialized.localizedDescription }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await run { try await self.repository.startFlowBranch(kind, name: name, base: base, config: config) }
    }

    func finish(_ kind: GitFlowKind, name: String, options: GitFlowFinishOptions) async {
        guard let config else { return errorMessage = GitFlowError.notInitialized.localizedDescription }
        await run { try await self.repository.finishFlowBranch(kind, name: name, config: config, options: options) }
    }

    /// Closes the sheet on success; a failure stays in it, and the repository refreshes either way,
    /// since a conflicted finish still moved branches.
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
