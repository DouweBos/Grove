// CILogTests.swift
// GroveTests
//
// Job logs: fetched through GitHub's redirect without leaking the token, split by step, folded by group.

import Foundation
import SwiftUI
import Testing
@testable import Grove

@MainActor
struct CILogTests {

    // MARK: Fetching

    @Test func theLogIsFetchedFromTheRedirectWithoutTheToken() async throws {
        let http = FakeHTTPClient(responses: { request in
            request.url?.host == "api.github.com"
                ? .init(status: 302, headers: ["Location": "https://results.blob.example.net/log.txt?sig=abc"])
                : .init(body: Data("2026-09-01T10:00:00.0000000Z Hello\n".utf8))
        })
        let log = try await CIHostTests.github(http).log(jobID: 5)

        #expect(log == "2026-09-01T10:00:00.0000000Z Hello\n")
        #expect(http.requests.map { $0.url?.absoluteString ?? "" } == [
            "https://api.github.com/repos/o/r/actions/jobs/5/logs", "https://results.blob.example.net/log.txt?sig=abc"
        ])
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(http.requests[1].value(forHTTPHeaderField: "Authorization") == nil, "The signed storage URL must not get the token")
    }

    @Test func logErrorsSurface() async {
        let gone = CIHostTests.github(FakeHTTPClient { _ in (410, #"{"message":"Logs have expired"}"#) })
        await #expect(throws: HostingError.http(status: 410, message: "Logs have expired")) { _ = try await gone.log(jobID: 5) }
        let refused = CIHostTests.github(FakeHTTPClient { _ in (401, "") })
        await #expect(throws: HostingError.notSignedIn(.github)) { _ = try await refused.log(jobID: 5) }
        let storage = CIHostTests.github(FakeHTTPClient(responses: { request in
            request.url?.host == "api.github.com" ? .init(status: 302, headers: ["Location": "https://blob.example.net/x"]) : .init(status: 404)
        }))
        await #expect(throws: HostingError.http(status: 404, message: "")) { _ = try await storage.log(jobID: 5) }
    }

    // MARK: Lines

    @Test func timestampsAreSplitOff() {
        let (date, rest) = CILogParser.split("2026-09-01T10:00:05.2500000Z ##[group]Run tests")
        #expect(date == GitDate.parse("2026-09-01T10:00:05Z")?.addingTimeInterval(0.25) && rest == "##[group]Run tests")
        #expect(CILogParser.split("2026-09-01T10:00:05Z plain").date == GitDate.parse("2026-09-01T10:00:05Z"))
        let leapDay = CILogParser.split("2024-02-29T23:59:59.9Z x").date?.timeIntervalSince(GitDate.parse("2024-02-29T23:59:59Z")!) ?? 0
        #expect(abs(leapDay - 0.9) < 0.0001)
        let continuation = CILogParser.split("    at Object.<anonymous> (index.js:1:1)")
        #expect(continuation.date == nil && continuation.rest == "    at Object.<anonymous> (index.js:1:1)")
        #expect(CILogParser.split("2026-09-01 10:00:05 not a log stamp").date == nil)
    }

    @Test func markersClassifyLines() {
        #expect(CILogParser.classify("##[error]Boom").kind == .error && CILogParser.classify("##[error]Boom").text == "Boom")
        #expect(CILogParser.classify("##[warning]Hm").kind == .warning && CILogParser.classify("##[group]Run x").kind == .group)
        #expect(CILogParser.classify("[command]/usr/bin/git version").kind == .command)
        #expect(CILogParser.classify("#include <stdio.h>").kind == .plain && CILogParser.classify("[1/3] Compiling").kind == .plain)
    }

    // MARK: Steps

    private func step(_ number: Int, _ name: String, _ start: String?, _ end: String?, _ status: CIRunStatus = .success) -> CIStep {
        CIStep(number: number, name: name, status: status, startedDate: start.flatMap(GitDate.parse), completedDate: end.flatMap(GitDate.parse))
    }

    private func job(_ steps: [CIStep]) -> CIJob {
        CIJob(id: 5, runID: 1, name: "build", status: .failure, startedDate: nil, completedDate: nil, steps: steps, webURL: "")
    }

    @Test func linesGoToTheStepRunningAtTheirTimestamp() {
        let log = """
        \u{FEFF}2026-09-01T10:00:00.1000000Z Current runner version: '2.328.0'
        2026-09-01T10:00:01.5000000Z Complete job name: build
        2026-09-01T10:00:02.2000000Z ##[group]Run swift build\r
        2026-09-01T10:00:02.3000000Z shell: /bin/bash
        2026-09-01T10:00:02.4000000Z ##[endgroup]
        2026-09-01T10:00:09.0000000Z Compiling
        a continuation line without a timestamp
        2026-09-01T10:00:12.0000000Z ##[error]Process completed with exit code 1.
        2026-09-01T10:00:20.0000000Z Cleaning up orphan processes

        """
        let document = CILogParser.parse(log, job: job([
            step(1, "Set up job", "2026-09-01T10:00:00Z", "2026-09-01T10:00:02Z"),
            step(2, "Build", "2026-09-01T10:00:02Z", "2026-09-01T10:00:12Z", .failure),
            step(3, "Upload", nil, nil, .skipped),
            step(4, "Complete job", "2026-09-01T10:00:20Z", "2026-09-01T10:00:20Z")
        ]))

        #expect(document.isSplitBySteps && document.sections.map(\.id) == [1, 2, 3, 4])
        #expect(document.sections[0].lines.map(\.text) == ["Current runner version: '2.328.0'", "Complete job name: build"])
        #expect(document.sections[1].lines.map(\.text) == ["Run swift build", "shell: /bin/bash", "Compiling",
                                                           "a continuation line without a timestamp",
                                                           "Process completed with exit code 1."])
        #expect(document.sections[1].lines.map(\.number) == [1, 2, 3, 4, 5], "Numbering restarts per step and skips nothing")
        #expect(document.sections[1].lines.last?.kind == .error)
        #expect(document.sections[2].lines.isEmpty && document.sections[3].lines.map(\.text) == ["Cleaning up orphan processes"])
        #expect(document.lineCount == 8)
        #expect(Set(document.sections.flatMap(\.lines).map(\.id)).count == 8, "Line ids are unique across steps")
    }

    @Test func stepsSharingASecondSplitAtTheNextStepsOpeningLine() {
        let log = """
        2026-09-01T10:00:00.1000000Z Set up line
        2026-09-01T10:00:00.2000000Z Still setting up
        2026-09-01T10:00:00.6000000Z ##[group]Run echo hi
        2026-09-01T10:00:00.7000000Z ##[endgroup]
        2026-09-01T10:00:00.8000000Z hi
        2026-09-01T10:00:00.9000000Z Post job cleanup.
        2026-09-01T10:00:00.9500000Z cleaned
        """
        let sameSecond = "2026-09-01T10:00:00Z"
        let document = CILogParser.parse(log, job: job([
            step(1, "Set up job", sameSecond, sameSecond), step(2, "Run echo hi", sameSecond, sameSecond),
            step(3, "Post Run actions/checkout@v4", sameSecond, sameSecond)
        ]))
        #expect(document.sections.map { $0.lines.map(\.text) } == [
            ["Set up line", "Still setting up"], ["Run echo hi", "hi"], ["Post job cleanup.", "cleaned"]
        ])
    }

    @Test func groupsFoldTheirLinesAndEndMarkersDisappear() {
        let log = """
        2026-09-01T10:00:00.1000000Z before
        2026-09-01T10:00:00.2000000Z ##[group]Environment
        2026-09-01T10:00:00.3000000Z A=1
        2026-09-01T10:00:00.4000000Z B=2
        2026-09-01T10:00:00.5000000Z ##[endgroup]
        2026-09-01T10:00:00.6000000Z after
        """
        let lines = CILogParser.parse(log, job: job([step(1, "Only", "2026-09-01T10:00:00Z", nil)])).sections[0].lines
        let header = lines[1]
        #expect(lines.map(\.text) == ["before", "Environment", "A=1", "B=2", "after"])
        #expect(header.kind == .group && header.group == nil)
        #expect(lines.map(\.group) == [nil, nil, header.id, header.id, nil])
    }

    @Test func withoutStepTimesTheLogIsOneSection() {
        let log = "2026-09-01T10:00:00.1000000Z ##[group]Setup\n2026-09-01T10:00:00.2000000Z inner\n2026-09-01T10:00:00.3000000Z ##[endgroup]\n"
        let untimed = CILogParser.parse(log, job: job([step(1, "A", nil, nil)]))
        #expect(!untimed.isSplitBySteps && untimed.sections.count == 1 && untimed.sections[0].title == "build")
        #expect(untimed.sections[0].lines.map(\.text) == ["Setup", "inner"] && untimed.sections[0].lines[1].group == 0)

        let unstamped = CILogParser.parse("plain output\nmore\n", job: job([step(1, "A", "2026-09-01T10:00:00Z", nil)]))
        #expect(!unstamped.isSplitBySteps && unstamped.sections[0].lines.map(\.text) == ["plain output", "more"])
    }

    @Test func escapeSequencesAreStripped() {
        #expect(ANSIParser.strip("\u{1B}[36;1mbuild\u{1B}[0m done") == "build done")
        #expect(ANSIParser.strip("no escapes") == "no escapes" && ANSIParser.strip("cut \u{1B}[3") == "cut ")
    }

    // MARK: View model

    private let failedRun = MockData.ciRuns[3]

    @Test func aFinishedJobShowsItsLogWithTheFailedStepOpen() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)

        await detail.show(failedRun)

        let log = detail.log
        let failedStep = try? #require(log.job?.steps.first { $0.status == .failure })
        #expect(log.job?.status == .failure && log.document?.isSplitBySteps == true && !log.isLoading)
        #expect(log.expandedSteps == [failedStep?.number ?? -1])
        #expect(log.rows.contains { if case .line(let line) = $0 { line.kind == .error } else { false } })
        #expect(log.rows.filter { if case .step = $0 { true } else { false } }.count == log.job?.steps.count)
        #expect(log.plainText.contains("Process completed with exit code 65.") && !log.plainText.contains("\u{1B}"))
    }

    @Test func stepsAndGroupsFold() async throws {
        let log = CILogViewModel(repository: MockGitRepository())
        await log.show(MockData.ciJobs(for: failedRun)[1])
        let section = try #require(log.document?.sections.first { $0.step?.status == .failure })
        let header = try #require(section.lines.first { $0.kind == .group })
        let folded = section.lines.filter { $0.group == header.id }
        #expect(!folded.isEmpty && !log.rows.contains(.line(folded[0])), "Groups start folded")

        log.toggleGroup(header)
        #expect(log.rows.contains(.line(folded[0])))

        log.toggleStep(section)
        #expect(!log.rows.contains(.line(header)) && log.rows.contains(.step(section)))
    }

    @Test func runningJobsShowStepsAndFetchNoLog() async {
        let repo = MockGitRepository()
        let log = CILogViewModel(repository: repo)
        let running = MockData.ciJobs(for: MockData.ciRuns[0])[1]

        await log.show(running)

        #expect(log.isWaitingForJob && repo.ci.logRequests.isEmpty && log.document?.lineCount == 0)
        #expect(log.rows.count == running.steps.count)
    }

    @Test func onlyFinishedJobsAreCachedAndAFinishedJobLoadsItsLog() async {
        let repo = MockGitRepository()
        let log = CILogViewModel(repository: repo)
        let jobs = MockData.ciJobs(for: failedRun)

        await log.show(jobs[0])
        await log.show(jobs[1])
        await log.show(jobs[0])
        #expect(repo.ci.logRequests == [jobs[0].id, jobs[1].id])

        // The same job, first running and then done: the log is read once it exists.
        let running = MockData.ciJobs(for: MockData.ciRuns[0])[1]
        let done = CIJob(id: running.id, runID: running.runID, name: running.name, status: .success, startedDate: running.startedDate,
                         completedDate: Date(), steps: running.steps, webURL: running.webURL)
        repo.ci.logs[running.id] = "2026-09-01T10:00:00.0000000Z done\n"
        await log.show(running)
        await log.show(done)
        #expect(repo.ci.logRequests.last == running.id && log.document?.lineCount == 1 && !log.isWaitingForJob)
    }

    @Test func aFailedLogReadKeepsTheStepsAndCanBeRetried() async {
        let repo = MockGitRepository()
        let log = CILogViewModel(repository: repo)
        let job = MockData.ciJobs(for: failedRun)[1]
        repo.ci.error = .http(status: 410, message: "Logs have expired")

        await log.show(job)
        #expect(log.errorMessage == "Logs have expired" && log.rows.count == job.steps.count && !log.isLoading)

        repo.ci.error = nil
        await log.reload()
        #expect(log.errorMessage == nil && log.document?.lineCount ?? 0 > 0)
    }
}

// MARK: - Colors and search

@MainActor
struct CILogStyleTests {

    @Test func colorsAndWeightsBecomeSpans() {
        let spans = ANSIParser.spans("\u{1B}[31;1merror:\u{1B}[0m plain \u{1B}[3;4;92mok\u{1B}[23m!\u{1B}[39;24m end")
        #expect(spans.map(\.text) == ["error:", " plain ", "ok", "!", " end"])
        #expect(spans[0].color == .red && spans[0].isBold && spans[1].isPlain)
        #expect(spans[2].color == .green && spans[2].isItalic && spans[2].isUnderlined, "Bright colors fold into the base ones")
        #expect(!spans[3].isItalic && spans[3].isUnderlined && spans[4].isPlain)
        #expect(ANSIParser.spans("no escapes") == [ANSISpan(text: "no escapes")])
    }

    @Test func otherSequencesAndBackgroundsAreDropped() {
        #expect(ANSIParser.spans("\u{1B}[2Kcleared\u{1B}[1Aup").map(\.text) == ["cleared", "up"])
        let spans = ANSIParser.spans("\u{1B}[41mred background\u{1B}[0m \u{1B}[48;5;196;33myellow")
        #expect(spans[0].isPlain && spans.last?.color == .yellow, "A background's extra codes aren't read as styles")
        #expect(ANSIParser.spans("\u{1B}[mreset") == [ANSISpan(text: "reset")])
    }

    @Test func extendedColorsQuantiseToTheEight() {
        #expect(ANSIParser.spans("\u{1B}[38;5;196mx")[0].color == .red)
        #expect(ANSIParser.spans("\u{1B}[38;5;10mx")[0].color == .green)
        #expect(ANSIParser.spans("\u{1B}[38;2;40;120;255mx")[0].color == .blue)
        #expect(ANSIParser.spans("\u{1B}[38;2;255;0;255;1mx")[0] == ANSISpan(text: "x", color: .magenta, isBold: true))
        #expect(ANSIParser.quantise(red: 0, green: 200, blue: 210) == .cyan && ANSIParser.quantise(red: 250, green: 210, blue: 0) == .yellow)
        #expect(ANSIParser.quantise(palette: 240) == .black && ANSIParser.quantise(palette: 252) == .white)
        #expect(ANSIParser.quantise(red: 128, green: 128, blue: 128) == .black)
    }

    @Test func searchMarksEveryOccurrenceAcrossStyles() {
        let text = CILogText.attributed("\u{1B}[32mPass\u{1B}[0med: passing", searchText: "pass")
        let marked = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(String(text.characters) == "Passed: passing" && marked == ["Pass", "pass"])
    }

    @Test func searchFindsLinesInClosedStepsAndFoldedGroups() async throws {
        let log = CILogViewModel(repository: MockGitRepository())
        let job = MockData.ciJobs(for: MockData.ciRuns[3])[1]
        await log.show(job)
        let rowsBefore = log.rows.count

        await log.setSearchText("SHELL:")

        let timedSteps = job.steps.filter { $0.startedDate != nil && !["Set up job", "Complete job"].contains($0.name) }
        #expect(log.matches.count == timedSteps.count && log.currentMatchIndex == 0)
        let first = try #require(log.currentMatch)
        #expect(log.rows.contains { $0.id == first } && log.rows.count > rowsBefore, "The first match's step and group open")

        log.nextMatch()
        #expect(log.currentMatchIndex == 1 && log.rows.contains { $0.id == log.currentMatch })
        log.previousMatch()
        log.previousMatch()
        #expect(log.currentMatchIndex == log.matches.count - 1, "Navigation wraps around")

        await log.setSearchText("no such text")
        #expect(log.matches.isEmpty && log.currentMatch == nil)
        log.nextMatch()
        await log.setSearchText("")
        #expect(log.matches.isEmpty && log.currentMatchIndex == nil)
    }

    @Test func searchIgnoresEscapeSequences() async {
        let repo = MockGitRepository()
        let job = MockData.ciJobs(for: MockData.ciRuns[2])[0]
        repo.ci.logs[job.id] = "2026-09-01T10:00:00.0000000Z \u{1B}[1mComp\u{1B}[0miling\n"
        let log = CILogViewModel(repository: repo)
        await log.show(job)

        await log.setSearchText("compiling")

        #expect(log.matches.count == 1)
    }
}
