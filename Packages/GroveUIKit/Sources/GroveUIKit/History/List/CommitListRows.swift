// History/List/CommitListRows.swift
// GroveUIKit
//
// The commit table's rows: in the graph layout each day's commits follow a header for that day.

#if os(macOS)
import Foundation
import GroveKit

/// Consecutive commits from one calendar day.
nonisolated struct CommitDayGroup: Identifiable, Sendable {
    /// The first commit's SHA: in topological order a day can recur, so the day itself isn't unique.
    let id: String
    let date: Date
    /// Indices into the commits grouped.
    var range: Range<Int>
}

enum CommitListRow: Equatable {
    /// A day's header, above the commit at `firstCommit`.
    case day(Date, firstCommit: Int)
    case commit(Int)
}

/// Looked up rather than listed: a day's header sits before its first commit, so a row is found by a binary search
/// over the days, and 100k commits need no 100k-row array.
struct CommitListRows {
    private var groups: [CommitDayGroup] = []
    private var commitCount = 0
    private var grouped = false

    init() {}

    init(_ commits: [CommitInfo], grouped: Bool) {
        commitCount = commits.count
        self.grouped = grouped
        if grouped { groups = Self.groups(commits) }
    }

    init(groups: [CommitDayGroup], commitCount: Int) {
        self.groups = groups
        self.commitCount = commitCount
        grouped = true
    }

    var count: Int { commitCount + (grouped ? groups.count : 0) }

    func row(_ row: Int) -> CommitListRow {
        guard grouped else { return .commit(row) }
        // The last day whose header is at or above `row`.
        var low = 0, high = groups.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if groups[mid].range.lowerBound + mid <= row { low = mid } else { high = mid - 1 }
        }
        let header = groups[low].range.lowerBound + low
        return row == header ? .day(groups[low].date, firstCommit: groups[low].range.lowerBound) : .commit(row - low - 1)
    }

    func row(ofCommit index: Int) -> Int {
        guard grouped else { return index }
        var low = 0, high = groups.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if groups[mid].range.lowerBound <= index { low = mid } else { high = mid - 1 }
        }
        return index + low + 1
    }

    func commitIndex(atRow row: Int) -> Int? {
        guard row >= 0, row < count, case .commit(let index) = self.row(row) else { return nil }
        return index
    }

    /// Every row in order, for tests.
    var rows: [CommitListRow] { (0..<count).map { row($0) } }
    var rowOfCommit: [Int] { (0..<commitCount).map { row(ofCommit: $0) } }

    /// Consecutive commits from the same calendar day share a group. Calendar math runs only when the day changes,
    /// so 100k commits group in a few milliseconds.
    nonisolated static func groups(_ commits: [CommitInfo], calendar: Calendar = .current) -> [CommitDayGroup] {
        var result: [CommitDayGroup] = []
        var dayStart = Date.distantFuture
        var dayEnd = Date.distantPast
        var groupStart = 0
        commits.withUnsafeBufferPointer { buffer in
            for index in buffer.indices {
                let date = buffer[index].committerDate
                if index > 0, date >= dayStart, date < dayEnd { continue }
                if index > 0 { result[result.count - 1].range = groupStart..<index }
                dayStart = calendar.startOfDay(for: date)
                dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
                groupStart = index
                result.append(CommitDayGroup(id: buffer[index].id, date: date, range: index..<index + 1))
            }
        }
        if !result.isEmpty { result[result.count - 1].range = groupStart..<commits.count }
        return result
    }
}

/// A ref beside a commit's subject: a local branch and its same-named remote branch collapse into one.
struct CommitDisplayRef: Identifiable, Equatable {
    enum Kind: Equatable { case local(isHEAD: Bool), remote, tag }
    let id: String
    let name: String
    let fullName: String
    let kind: Kind
    let isOnRemote: Bool

    /// HEAD first, then local branches, remote-only branches and tags.
    static func display(branches: [BranchInfo], tags: [TagInfo]) -> [CommitDisplayRef] {
        let locals = branches.filter { !$0.isRemote }
        let remotes = branches.filter(\.isRemote)
        func remoteTwin(of local: BranchInfo) -> BranchInfo? {
            remotes.first { $0.name.split(separator: "/", maxSplits: 1).last.map(String.init) == local.name }
        }
        let twinned = Set(locals.compactMap { remoteTwin(of: $0)?.name })
        let localRefs = locals.sorted { $0.isHEAD && !$1.isHEAD }.map { local in
            let twin = remoteTwin(of: local)
            return CommitDisplayRef(id: "l:\(local.name)", name: local.name,
                                    fullName: twin.map { "\(local.name) (also \($0.name))" } ?? local.name,
                                    kind: .local(isHEAD: local.isHEAD), isOnRemote: twin != nil)
        }
        let remoteRefs = remotes.filter { !twinned.contains($0.name) }.map {
            CommitDisplayRef(id: "r:\($0.name)", name: $0.name, fullName: $0.name, kind: .remote, isOnRemote: false)
        }
        let tagRefs = tags.map {
            CommitDisplayRef(id: "t:\($0.name)", name: $0.name, fullName: "tag \($0.name)", kind: .tag, isOnRemote: false)
        }
        return localRefs + remoteRefs + tagRefs
    }
}
#endif
