// Domain/CI/CILogParser.swift
// Grove
//
// A job's plain-text log into steps, groups and marked lines.

import Foundation

nonisolated struct CILogLine: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case plain, group, error, warning, notice, command, debug }

    /// Position in the whole log, starting at 0.
    let id: Int
    /// Line number within its step, starting at 1.
    let number: Int
    /// Without timestamp and `##[…]` marker; may still hold ANSI escapes.
    let text: String
    let kind: Kind
    /// The `id` of the group header this line is folded under.
    let group: Int?
}

/// The lines of one step, or of the whole job when they couldn't be told apart.
nonisolated struct CILogSection: Identifiable, Hashable, Sendable {
    /// The step's number; 0 for the whole-job fallback.
    let id: Int
    let title: String
    let step: CIStep?
    let lines: [CILogLine]
}

nonisolated struct CILogDocument: Hashable, Sendable {
    let sections: [CILogSection]
    /// False when the log is one section because its lines couldn't be assigned to steps.
    let isSplitBySteps: Bool
    let lineCount: Int
    /// Characters in the longest line, to size a non-wrapping view.
    let longestLine: Int

    /// Steps without any log lines, for a job that's still running.
    init(steps job: CIJob) {
        sections = job.steps.map { CILogSection(id: $0.number, title: $0.name, step: $0, lines: []) }
        isSplitBySteps = true
        lineCount = 0
        longestLine = 0
    }

    init(sections: [CILogSection], isSplitBySteps: Bool, longestLine: Int) {
        self.sections = sections
        self.isSplitBySteps = isSplitBySteps
        lineCount = sections.reduce(0) { $0 + $1.lines.count }
        self.longestLine = longestLine
    }
}

nonisolated enum CILogParser {

    private struct Entry {
        let date: Date?
        let text: String
        let kind: CILogLine.Kind
        let isStepStart: Bool
    }

    /// Splits `text` by the job's steps: a line belongs to the step running at its timestamp.
    /// Step times only have second resolution, so within a shared second a step's opening line decides.
    static func parse(_ text: String, job: CIJob) -> CILogDocument {
        let entries = entries(of: text)
        let timed = job.steps.filter { $0.startedDate != nil }
        guard !timed.isEmpty, entries.contains(where: { $0.date != nil }) else {
            let (lines, longest) = lines(entries[...], firstID: 0)
            return CILogDocument(sections: [CILogSection(id: 0, title: job.name, step: nil, lines: lines)], isSplitBySteps: false,
                                 longestLine: longest)
        }

        var ranges: [Int: Range<Int>] = [:]
        var current = 0
        var start = 0
        for (index, entry) in entries.enumerated() {
            guard let date = entry.date else { continue }
            let second = date.timeIntervalSince1970.rounded(.down)
            var next = current
            var isOpening = entry.isStepStart
            while next + 1 < timed.count, let began = timed[next + 1].startedDate?.timeIntervalSince1970.rounded(.down) {
                let currentEnded = timed[next].completedDate.map { $0.timeIntervalSince1970.rounded(.down) < second } ?? false
                guard began < second || (began == second && (isOpening || currentEnded)) else { break }
                // An opening line opens one step, however many share its second.
                if began == second, !currentEnded { isOpening = false }
                next += 1
            }
            if next != current {
                ranges[timed[current].number] = start..<index
                (current, start) = (next, index)
            }
        }
        ranges[timed[current].number] = start..<entries.count

        var longest = 0
        var nextID = 0
        let sections = job.steps.map { step -> CILogSection in
            let (lines, width) = ranges[step.number].map { lines(entries[$0], firstID: nextID) } ?? ([], 0)
            nextID += ranges[step.number]?.count ?? 0
            longest = max(longest, width)
            return CILogSection(id: step.number, title: step.name, step: step, lines: lines)
        }
        return CILogDocument(sections: sections, isSplitBySteps: true, longestLine: longest)
    }

    // MARK: - Lines

    private static func entries(of text: String) -> [Entry] {
        // `\r\n` is one Character, so it has to be named to split on it.
        var raw = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
        if raw.last?.isEmpty == true { raw.removeLast() }
        return raw.map { line in
            var line = line
            if line.hasPrefix("\u{FEFF}") { line = line.dropFirst() }
            let (date, rest) = split(line)
            let (kind, body) = classify(rest)
            // `Run …` groups open run and uses steps; post steps and the closing step open with these lines.
            let startsStep = (kind == .group && body.hasPrefix("Run ")) || body.hasPrefix("Post job cleanup.")
                || body.hasPrefix("Cleaning up orphan processes")
            return Entry(date: date, text: String(body), kind: kind, isStepStart: startsStep)
        }
    }

    /// Numbers the lines of one section and folds them under their `##[group]`; `##[endgroup]` lines are dropped.
    private static func lines(_ entries: ArraySlice<Entry>, firstID: Int) -> (lines: [CILogLine], longest: Int) {
        var lines: [CILogLine] = []
        lines.reserveCapacity(entries.count)
        var group: Int?
        var longest = 0
        var id = firstID
        for entry in entries {
            defer { id += 1 }
            if entry.kind == .plain, entry.text == endGroup {
                group = nil
                continue
            }
            let isHeader = entry.kind == .group
            lines.append(CILogLine(id: id, number: lines.count + 1, text: entry.text, kind: entry.kind, group: isHeader ? nil : group))
            if isHeader { group = id }
            longest = max(longest, entry.text.utf8.count)
        }
        return (lines, longest)
    }

    private static let endGroup = "##[endgroup]"
    private static let markers: [(String, CILogLine.Kind)] = [
        ("##[group]", .group), ("##[error]", .error), ("##[warning]", .warning), ("##[notice]", .notice),
        ("##[command]", .command), ("[command]", .command), ("##[debug]", .debug), ("##[section]", .plain)
    ]

    static func classify(_ line: Substring) -> (kind: CILogLine.Kind, text: Substring) {
        guard line.hasPrefix("#") || line.hasPrefix("[") else { return (.plain, line) }
        for (marker, kind) in markers where line.hasPrefix(marker) {
            return (kind, line.dropFirst(marker.count))
        }
        return (.plain, line)
    }

    /// `2026-09-01T10:00:00.1234567Z text` → the time and `text`; lines without a timestamp come back whole.
    static func split(_ line: Substring) -> (date: Date?, rest: Substring) {
        let bytes = line.utf8
        guard bytes.count >= 20 else { return (nil, line) }
        var digits = [Int](repeating: 0, count: 6)
        let layout: [(offset: Int, length: Int)] = [(0, 4), (5, 2), (8, 2), (11, 2), (14, 2), (17, 2)]
        var index = bytes.startIndex
        var position = 0
        var field = 0
        var fraction = 0.0
        var scale = 0.1
        var end: Substring.UTF8View.Index?
        scan: while index != bytes.endIndex, position < 40 {
            let byte = bytes[index]
            if position < 19 {
                if field < 6, position >= layout[field].offset, position < layout[field].offset + layout[field].length {
                    guard byte >= 48, byte <= 57 else { return (nil, line) }
                    digits[field] = digits[field] * 10 + Int(byte - 48)
                    if position == layout[field].offset + layout[field].length - 1 { field += 1 }
                } else {
                    let expected: UInt8 = position == 10 ? 84 : position < 10 ? 45 : 58
                    guard byte == expected else { return (nil, line) }
                }
            } else if byte == 90 {
                end = index
                break scan
            } else if byte >= 48, byte <= 57, position > 19 {
                fraction += Double(byte - 48) * scale
                scale /= 10
            } else if !(byte == 46 && position == 19) {
                return (nil, line)
            }
            index = bytes.index(after: index)
            position += 1
        }
        guard let end else { return (nil, line) }
        var rest = line[bytes.index(after: end)...]
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        let days = daysFromCivil(year: digits[0], month: digits[1], day: digits[2])
        let seconds = Double(days * 86_400 + digits[3] * 3600 + digits[4] * 60 + digits[5]) + fraction
        return (Date(timeIntervalSince1970: seconds), rest)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar; ISO8601 parsing is far too slow for every log line.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
