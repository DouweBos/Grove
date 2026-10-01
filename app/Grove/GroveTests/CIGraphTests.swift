// CIGraphTests.swift
// GroveTests
//
// The workflow graph: jobs and `needs` read from the file, laid out in columns, with the host's jobs matched onto them.

import CoreGraphics
import Foundation
import Testing
@testable import Grove

@MainActor
struct CIGraphTests {

    private let workflow = """
    name: E2E Smoke
    on:
      workflow_dispatch:
    jobs:
      check-trigger:
        name: Check Trigger Conditions
        runs-on: ubuntu-latest
        steps:
          - run: echo "needs: nothing"   # not a job property
      build-ios:
        name: Build iOS Simulator
        needs: check-trigger
      build-android:
        name: "Build Android Nightly APK"
        needs:
          - check-trigger
      fetch-test-data:
        name: Fetch Maestro Test Data
        needs: [check-trigger]
      smoke-ios:
        name: Smoke Test iOS (${{ matrix.device }})
        needs: [build-ios, fetch-test-data]
        strategy:
          matrix:
            device: [iPhone, iPad]
      smoke-android:
        name: Smoke Test Android
        needs: [build-android, fetch-test-data]
      deploy:
        uses: ./.github/workflows/deploy.yml
        needs: [smoke-android, check-trigger, build-android]
      report:
        if: |
          always()
        needs:
          [
            smoke-ios,
            smoke-android, missing-job,
          ]
    """

    private func job(_ id: Int, _ name: String, _ status: CIRunStatus = .success) -> CIJob {
        CIJob(id: id, runID: 1, name: name, status: status, startedDate: nil, completedDate: nil, steps: [], webURL: "")
    }

    @Test func jobsAndTheirNeedsAreRead() {
        let jobs = WorkflowJobsParser.parse(workflow)
        #expect(jobs.map(\.key) == ["check-trigger", "build-ios", "build-android", "fetch-test-data", "smoke-ios", "smoke-android",
                                    "deploy", "report"])
        #expect(jobs[0].needs.isEmpty && jobs[0].title == "Check Trigger Conditions", "Steps' text isn't read as the job's")
        #expect(jobs[1].needs == ["check-trigger"] && jobs[2].needs == ["check-trigger"] && jobs[3].needs == ["check-trigger"])
        #expect(jobs[2].title == "Build Android Nightly APK" && jobs[6].title == "deploy")
        #expect(jobs[7].needs == ["smoke-ios", "smoke-android", "missing-job"])
        #expect(WorkflowJobsParser.parse("on: push\n").isEmpty)
    }

    @Test func columnsFollowTheLongestChainOfNeeds() {
        let graph = CIGraph.build(definitions: WorkflowJobsParser.parse(workflow), jobs: [])
        #expect(graph.columns.map { $0.map(\.id) } == [
            ["check-trigger"], ["build-ios", "build-android", "fetch-test-data"], ["smoke-ios", "smoke-android"], ["report", "deploy"]
        ])
        #expect(graph.nodes.allSatisfy { $0.status == nil }, "Jobs the host hasn't created yet are shown as not started")
        #expect(graph.edges.contains { $0 == ("fetch-test-data", "smoke-android") } && !graph.edges.contains { $0.from == "missing-job" })
        #expect(graph.edges.count == 10, "Links another path implies aren't drawn")
        #expect(!graph.edges.contains { $0 == ("check-trigger", "deploy") || $0 == ("build-android", "deploy") })
    }

    @Test func theHostsJobsLandOnTheirDefinitions() {
        let graph = CIGraph.build(definitions: WorkflowJobsParser.parse(workflow), jobs: [
            job(1, "Check Trigger Conditions"), job(2, "Build Android Nightly APK", .inProgress), job(3, "Build iOS Simulator", .skipped),
            job(4, "Smoke Test iOS (iPhone)", .failure), job(5, "Smoke Test iOS (iPad)"), job(6, "Smoke Test Android (Phone, 34)"),
            job(7, "deploy / Upload"), job(8, "Something else entirely", .queued)
        ])
        let byID = Dictionary(graph.nodes.map { ($0.id, $0) }) { first, _ in first }
        #expect(byID["check-trigger"]?.status == .success && byID["build-android"]?.status == .inProgress)
        #expect(byID["build-ios"]?.status == .skipped && byID["fetch-test-data"]?.status == nil)
        #expect(byID["smoke-ios"]?.jobs.map(\.id) == [4, 5] && byID["smoke-ios"]?.status == .failure, "Matrix jobs share their node")
        #expect(byID["smoke-android"]?.jobs.map(\.id) == [6] && byID["deploy"]?.jobs.map(\.id) == [7])
        #expect(byID["job-8"]?.column == 0, "A job the file doesn't account for still shows")
    }

    @Test func withoutTheFileEveryJobStandsAlone() {
        let graph = CIGraph.build(definitions: [], jobs: [job(1, "lint"), job(2, "build")])
        #expect(graph.columns.count == 1 && graph.nodes.map(\.title) == ["lint", "build"] && graph.edges.isEmpty)
    }

    @Test func aCycleDoesNotHang() {
        let graph = CIGraph.build(definitions: [WorkflowJobDefinition(key: "a", needs: ["b"]), WorkflowJobDefinition(key: "b", needs: ["a"])],
                                  jobs: [])
        #expect(graph.nodes.count == 2)
    }

    @Test func nodesDoNotOverlap() {
        let graph = CIGraph.build(definitions: WorkflowJobsParser.parse(workflow),
                                  jobs: [job(4, "Smoke Test iOS (iPhone)"), job(5, "Smoke Test iOS (iPad)")])
        let layout = CIGraphLayout(graph)
        let frames = Array(layout.frames.values)
        for (index, frame) in frames.enumerated() {
            #expect(!frames[(index + 1)...].contains { $0.intersects(frame) })
            #expect(CGRect(origin: .zero, size: layout.size).contains(frame))
        }
        #expect(layout.frames["smoke-ios"]?.height ?? 0 > CIGraphLayout.headerHeight, "A matrix node lists its jobs")
    }

    // MARK: View model

    @Test func theGraphReadsTheWorkflowAtTheRunsCommitOnce() async throws {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        let run = MockData.ciRuns[3]
        await detail.show(run)
        await detail.selectTab(.artifacts)
        await detail.selectTab(.jobs)
        await detail.show(run)

        #expect(repo.ci.workflowFileRequests == ["\(run.workflowPath)@\(run.headSHA)"])
        #expect(detail.graph.columns.map { $0.map(\.id) } == [["lint"], ["build"], ["notify"]])
        #expect(detail.graph.nodes.first { $0.id == "build" }?.status == .failure)

        let node = try #require(detail.graph.nodes.first { $0.id == "build" })
        await detail.open(node)
        #expect(detail.selectedJob?.id == node.jobs.first?.id)
    }

    @Test func anUnreadableFileStillShowsTheJobs() async {
        let repo = MockGitRepository()
        repo.ci.workflowFiles = [:]
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(MockData.ciRuns[3])

        #expect(detail.graphError == "Not Found" && detail.graph.nodes.count == 2 && detail.graph.columns.count == 1)
    }
}
