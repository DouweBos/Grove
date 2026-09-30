// Views/CI/CILogViewModel.swift
// Grove

import Foundation
import Observation

/// One visible row of a job log.
enum CILogRow: Identifiable, Hashable {
    case step(CILogSection)
    case line(CILogLine)

    var id: Int {
        switch self {
        case .step(let section): -1 - section.id
        case .line(let line): line.id
        }
    }
}

/// The selected job's log: its steps, which of them and their groups are open, and the rows that leaves visible.
@MainActor
@Observable
final class CILogViewModel {

    private(set) var job: CIJob?
    private(set) var document: CILogDocument?
    private(set) var rows: [CILogRow] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var expandedSteps: Set<Int> = []
    private(set) var expandedGroups: Set<Int> = []
    private(set) var searchText = ""
    /// Ids of the lines containing the search text, in log order.
    private(set) var matches: [Int] = []
    private(set) var currentMatchIndex: Int?

    // Finished jobs only: a running job's log isn't there yet, and logs are too big to keep many.
    @ObservationIgnored private var cache = LRUCache<Int, CILogDocument>(capacity: 8)

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    /// GitHub only serves a job's log once the job is done.
    var isWaitingForJob: Bool { job?.status.isActive == true }

    // MARK: - Loading

    /// Shows `job`'s steps at once and, when it has finished, its log under them.
    func show(_ job: CIJob?) async {
        guard let job else { return clear() }
        let previous = self.job
        guard previous != job || (document == nil && !isLoading) else { return }
        self.job = job
        errorMessage = nil
        if previous?.id != job.id {
            expandedSteps = []
            expandedGroups = []
        }
        if job.status.isActive || job.steps.isEmpty && job.status == .skipped {
            return apply(CILogDocument(steps: job), for: job)
        }
        if let cached = cache.value(for: job.id) { return apply(cached, for: job) }
        if previous?.id != job.id { apply(CILogDocument(steps: job), for: job) }
        await load(job)
    }

    func reload() async {
        guard let job, !job.status.isActive else { return }
        await load(job)
    }

    private func load(_ job: CIJob) async {
        isLoading = true
        defer { if self.job?.id == job.id { isLoading = false } }
        do {
            let text = try await repository.ciJobLog(jobID: job.id)
            let parsed = await Self.parse(text, job: job)
            cache.insert(parsed, for: job.id)
            guard self.job?.id == job.id else { return }
            errorMessage = nil
            apply(parsed, for: job)
            // Open what went wrong; a log that isn't split by steps has nothing to open.
            if expandedSteps.isEmpty { expandedSteps = Set(job.steps.filter { $0.status == .failure }.map(\.number)) }
            rebuildRows()
        } catch {
            guard self.job?.id == job.id else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Logs run to tens of megabytes, so they're parsed off the main actor.
    @concurrent
    private nonisolated static func parse(_ text: String, job: CIJob) async -> CILogDocument {
        CILogParser.parse(text, job: job)
    }

    private func apply(_ document: CILogDocument, for job: CIJob) {
        self.document = document
        rebuildRows()
        if !searchText.isEmpty { Task { await search() } }
    }

    private func clear() {
        job = nil
        document = nil
        rows = []
        isLoading = false
        errorMessage = nil
        matches = []
        currentMatchIndex = nil
    }

    // MARK: - Folding

    func isExpanded(_ section: CILogSection) -> Bool { expandedSteps.contains(section.id) }

    func toggleStep(_ section: CILogSection) {
        guard !section.lines.isEmpty else { return }
        expandedSteps.formSymmetricDifference([section.id])
        rebuildRows()
    }

    func toggleGroup(_ line: CILogLine) {
        guard line.kind == .group else { return }
        expandedGroups.formSymmetricDifference([line.id])
        rebuildRows()
    }

    private func rebuildRows() {
        guard let document else { return rows = [] }
        var visible: [CILogRow] = []
        for section in document.sections {
            if document.isSplitBySteps {
                visible.append(.step(section))
                guard expandedSteps.contains(section.id) else { continue }
            }
            for line in section.lines where line.group.map(expandedGroups.contains) ?? true {
                visible.append(.line(line))
            }
        }
        rows = visible
    }

    // MARK: - Search

    var currentMatch: Int? { currentMatchIndex.map { matches[$0] } }

    /// Finds the lines containing `text`, ignoring case and escape sequences, and goes to the first.
    func setSearchText(_ text: String) async {
        guard text != searchText else { return }
        searchText = text
        await search()
    }

    private func search() async {
        let query = searchText
        guard !query.isEmpty, let document else {
            matches = []
            currentMatchIndex = nil
            return
        }
        let found = await Self.lines(matching: query, in: document)
        guard query == searchText, document == self.document else { return }
        matches = found
        currentMatchIndex = nil
        if !found.isEmpty { show(match: 0) }
    }

    @concurrent
    private nonisolated static func lines(matching query: String, in document: CILogDocument) async -> [Int] {
        document.sections.flatMap(\.lines).filter { ANSIParser.strip($0.text).range(of: query, options: .caseInsensitive) != nil }.map(\.id)
    }

    func nextMatch() { step(by: 1) }

    func previousMatch() { step(by: -1) }

    private func step(by offset: Int) {
        guard !matches.isEmpty else { return }
        show(match: ((currentMatchIndex ?? -offset) + offset + matches.count) % matches.count)
    }

    /// Opens the step and group holding the match so its row exists to scroll to.
    private func show(match index: Int) {
        currentMatchIndex = index
        let id = matches[index]
        guard let section = document?.sections.first(where: { ($0.lines.first?.id ?? .max) <= id && id <= ($0.lines.last?.id ?? .min) }),
              let line = section.lines.first(where: { $0.id == id }) else { return }
        let opened = expandedSteps.insert(section.id).inserted
        let unfolded = line.group.map { expandedGroups.insert($0).inserted } ?? false
        if opened || unfolded { rebuildRows() }
    }

    // MARK: - Copying

    /// The whole log without escape sequences, one line per log line.
    var plainText: String {
        (document?.sections ?? []).flatMap(\.lines).map { ANSIParser.strip($0.text) }.joined(separator: "\n")
    }

    func plainText(of section: CILogSection) -> String {
        section.lines.map { ANSIParser.strip($0.text) }.joined(separator: "\n")
    }
}
