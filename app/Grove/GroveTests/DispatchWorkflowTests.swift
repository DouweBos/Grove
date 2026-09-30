// DispatchWorkflowTests.swift
// GroveTests
//
// Running a workflow by hand: reading its inputs from the definition on the chosen ref, the request sent,
// and the Actions tab picking up the run that starts.

import Foundation
import Testing
@testable import Grove

@MainActor
struct DispatchWorkflowTests {

    private func body(_ request: URLRequest?) -> [String: Any] {
        request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// A sheet on the mock repository, whose remote branches include `origin/main`.
    private func sheet(_ repo: MockGitRepository, workflowID: Int? = 2) -> DispatchWorkflowViewModel {
        let refs = RepositoryRefs(repository: repo)
        refs.replace(localBranches: MockData.branches.filter(\.isLocal), remoteBranches: MockData.branches.filter(\.isRemote),
                     tags: MockData.tags, remotes: MockData.remotes)
        return DispatchWorkflowViewModel(repository: repo, refs: refs, workflows: MockData.ciWorkflows, workflowID: workflowID)
    }

    // MARK: Host

    @Test func dispatchPostsTheRefAndInputs() async throws {
        let http = FakeHTTPClient { _ in (204, "") }
        try await CIHostTests.github(http).dispatch(CIDispatch(workflowID: 7, ref: "main", inputs: ["channel": "beta", "notarize": "true"]))

        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/repos/o/r/actions/workflows/7/dispatches")
        #expect(body(request)["ref"] as? String == "main")
        #expect(body(request)["inputs"] as? [String: String] == ["channel": "beta", "notarize": "true"])
    }

    @Test func theDefinitionIsReadRawFromTheRef() async throws {
        let http = FakeHTTPClient { _ in (200, "on: workflow_dispatch\n") }
        let file = try await CIHostTests.github(http).workflowFile(path: ".github/workflows/my release.yml", ref: "feature/a+b")

        #expect(file == "on: workflow_dispatch\n")
        #expect(http.requests[0].url?.absoluteString
                == "https://api.github.com/repos/o/r/contents/.github/workflows/my%20release.yml?ref=feature/a%2Bb")
        #expect(http.requests[0].value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
    }

    @Test func aRefusedDispatchSurfacesTheReason() async {
        let host = CIHostTests.github(FakeHTTPClient { _ in (422, #"{"message":"Required input 'version' not provided"}"#) })
        await #expect(throws: HostingError.http(status: 422, message: "Required input 'version' not provided")) {
            try await host.dispatch(CIDispatch(workflowID: 7, ref: "main"))
        }
    }

    // MARK: Sheet

    @Test func theSheetOffersEnabledWorkflowsAndReadsTheInputs() async {
        let repo = MockGitRepository()
        let vm = sheet(repo)

        await vm.load()

        #expect(vm.workflows.map(\.name) == ["CI", "Release"], "Disabled workflows can't be run")
        #expect(vm.ref == "main" && vm.refCandidates.contains("main") && !vm.refCandidates.contains("HEAD"))
        #expect(repo.ci.workflowFileRequests == [".github/workflows/release.yml@main"])
        #expect(vm.inputs.map(\.name) == ["channel", "version", "notarize"])
        #expect(vm.values == ["channel": "beta", "version": "", "notarize": "true"], "Inputs start at their defaults")
    }

    @Test func requiredInputsGateTheRunButtonAndEmptyOptionalOnesAreNotSent() async throws {
        let repo = MockGitRepository()
        let vm = sheet(repo)
        await vm.load()
        #expect(!vm.canSubmit)

        vm.setValue("1.4.0", for: try #require(vm.inputs.first { $0.name == "version" }))
        vm.setValue("false", for: try #require(vm.inputs.first { $0.name == "notarize" }))
        #expect(vm.canSubmit)
        var dispatched: CIDispatch?
        vm.onDispatched = { dispatched = $0 }

        await vm.submit()

        let expected = CIDispatch(workflowID: 2, ref: "main", inputs: ["channel": "beta", "version": "1.4.0", "notarize": "false"])
        #expect(repo.ci.dispatches == [expected] && dispatched == expected && vm.progressTitle == nil)
    }

    @Test func aWorkflowWithoutTheTriggerCannotBeRun() async {
        let repo = MockGitRepository()
        let vm = sheet(repo, workflowID: 1)

        await vm.load()
        #expect(vm.form == .notDispatchable && !vm.canSubmit)

        await vm.setWorkflow(2)
        #expect(vm.inputs.count == 3)
    }

    @Test func anUnreadableDefinitionFallsBackToFreeFormInputs() async throws {
        let repo = MockGitRepository()
        repo.ci.workflowFiles[".github/workflows/release.yml"] = "on: { workflow_dispatch: { inputs: { a: { type: boolean } } } }"
        let vm = sheet(repo)

        await vm.load()
        #expect(vm.form == .freeForm && vm.freeFormRows.count == 1 && vm.canSubmit)

        vm.setFreeFormRow(vm.freeFormRows[0], name: "a", value: "true")
        vm.addFreeFormRow()
        vm.addFreeFormRow()
        vm.setFreeFormRow(vm.freeFormRows[2], name: "b", value: "2")
        vm.removeFreeFormRow(vm.freeFormRows[2])
        await vm.submit()

        #expect(repo.ci.dispatches.first?.inputs == ["a": "true"], "Rows without a name are left out")
    }

    @Test func aMissingDefinitionAlsoFallsBackToFreeForm() async {
        let repo = MockGitRepository()
        repo.ci.workflowFiles = [:]
        let vm = sheet(repo)
        await vm.load()
        #expect(vm.form == .freeForm)
    }

    @Test func inputsAreReReadForAKnownRefOnly() async {
        let repo = MockGitRepository()
        let vm = sheet(repo)
        await vm.load()
        let other = vm.refCandidates.first { $0 != "main" } ?? ""

        await vm.setRef("ma")
        await vm.setRef(other)

        #expect(repo.ci.workflowFileRequests == [".github/workflows/release.yml@main", ".github/workflows/release.yml@\(other)"])
        #expect(!other.isEmpty && vm.ref == other)
    }

    @Test func aFailedDispatchKeepsTheSheetOpenWithTheError() async {
        let repo = MockGitRepository()
        let vm = sheet(repo, workflowID: 3)
        repo.ci.workflows = MockData.ciWorkflows.map { CIWorkflow(id: $0.id, name: $0.name, path: $0.path, isEnabled: true) }
        let all = DispatchWorkflowViewModel(repository: repo, refs: vm.refs, workflows: repo.ci.workflows, workflowID: 3)
        await all.load()
        #expect(all.form == .inputs([]) && all.canSubmit)
        var dispatched = false
        all.onDispatched = { _ in dispatched = true }
        repo.ci.error = .http(status: 422, message: "No ref found for: nope")

        await all.submit()

        #expect(all.errorMessage == "No ref found for: nope" && !dispatched && !all.isSubmitting)
    }

    // MARK: Actions tab

    @Test func afterADispatchTheNewRunIsSelectedAndPolledFast() async throws {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        let vm = session.ciVM
        await vm.refresh()
        await vm.setStatusFilter(.failure)

        session.handleAction(.runWorkflow)
        let sheet = try #require(vm.dispatch)
        #expect(sheet.workflowID == vm.selectedRun?.workflowID, "The sheet opens on the selected run's workflow")
        await sheet.setWorkflow(3)
        await sheet.load()
        await sheet.setWorkflow(2)
        sheet.setValue("1.4.0", for: try #require(sheet.inputs.first { $0.name == "version" }))
        await sheet.submit()

        #expect(vm.dispatch == nil && session.sidebarVM.selection == .ci)
        #expect(vm.query.isEmpty, "A filter that would hide the new run is cleared")
        let started = try #require(vm.selectedRun)
        #expect(started.event == "workflow_dispatch" && started.workflowID == 2 && started.status == .queued)
        #expect(!MockData.ciRuns.contains { $0.id == started.id } && vm.pollInterval == 5)
    }

    @Test func cancellingTheSheetStartsNothing() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        await vm.setWorkflowFilter(2)

        vm.beginDispatch()
        #expect(vm.dispatch?.workflowID == 2, "The sheet opens on the filtered workflow")
        vm.cancelDispatch()

        #expect(vm.dispatch == nil && repo.ci.dispatches.isEmpty)
    }
}
