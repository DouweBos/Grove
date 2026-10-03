// CIViewModelTests.swift
// GroveTests
//
// The Actions tab's list: what it reads, how filters re-read it, and what it shows when the host can't be reached.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct CIViewModelTests {

    @Test func refreshLoadsRunsAndWorkflowsAndSelectsTheNewest() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        #expect(!vm.hasLoaded)

        await vm.refresh()

        #expect(vm.hasLoaded && !vm.isLoading && vm.loadFailure == nil)
        #expect(vm.runs == MockData.ciRuns && vm.workflows == MockData.ciWorkflows)
        #expect(vm.selectedRun?.id == MockData.ciRuns[0].id)
        #expect(repo.ci.queries == [CIRunQuery()])
    }

    @Test func filtersReReadTheListFromTheHost() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()

        await vm.setWorkflowFilter(1)
        await vm.setBranchFilter("main")
        await vm.setStatusFilter(.success)
        await vm.setStatusFilter(.success)

        #expect(repo.ci.queries.last == CIRunQuery(workflowID: 1, branch: "main", status: .success))
        #expect(repo.ci.queries.count == 4, "An unchanged filter doesn't read again")
        #expect(vm.runs.map(\.id) == [146] && vm.selectedRun?.id == 146, "The selection moves to a run that's still listed")

        await vm.setStatusFilter(.queued)
        #expect(vm.runs.isEmpty && vm.selectedRun == nil && vm.loadFailure == nil)

        await vm.clearFilters()
        #expect(vm.query.isEmpty && vm.runs.count == MockData.ciRuns.count)
    }

    @Test func theSelectionSurvivesAReload() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        await vm.select(MockData.ciRuns[2])

        await vm.refresh()

        #expect(vm.selectedRun?.id == MockData.ciRuns[2].id)
    }

    @Test func anUnsupportedHostIsAStateNotAnError() async {
        let repo = MockGitRepository()
        repo.ci.error = .ciUnsupported(.gitlab)
        let vm = CIViewModel(repository: repo)

        await vm.refresh()

        #expect(vm.loadFailure == .unsupportedHost(.gitlab) && vm.runs.isEmpty && vm.hasLoaded)
    }

    @Test func aFailedReloadKeepsTheListOnScreen() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()

        repo.ci.error = .http(status: 403, message: "Resource not accessible")
        await vm.refresh()
        #expect(vm.loadFailure == .forbidden("Resource not accessible") && vm.runs.count == MockData.ciRuns.count)

        repo.ci.error = nil
        await vm.refresh()
        #expect(vm.loadFailure == nil)
    }

    @Test func anAnswerToAnOutdatedFilterIsDropped() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)

        async let slow: Void = vm.setStatusFilter(.failure)
        async let fast: Void = vm.setStatusFilter(.success)
        _ = await (slow, fast)

        #expect(vm.runs.allSatisfy { $0.status == vm.query.status })
        #expect(!vm.isLoading)
    }

    @Test func theBranchFilterOffersLocalBranchesAndTheFilteredOne() async {
        let repo = MockGitRepository()
        let refs = RepositoryRefs(repository: repo)
        refs.replace(localBranches: MockData.branches.filter(\.isLocal))
        let vm = CIViewModel(repository: repo, refs: refs)

        await vm.setBranchFilter("release/remote-only")

        #expect(vm.branchCandidates.contains("release/remote-only") && vm.branchCandidates.contains("main"))
        #expect(vm.branchCandidates == vm.branchCandidates.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
