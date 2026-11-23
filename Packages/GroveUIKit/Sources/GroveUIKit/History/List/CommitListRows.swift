// History/List/CommitListRows.swift
// GroveUIKit
//
// The commit table's rows: in the graph layout each day's commits follow a header for that day.

#if os(macOS)
import Foundation
import GroveKit

/// Consecutive commits from one calendar day.
struct CommitDayGroup: Identifiable {
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

struct CommitListRows {
    private(set) var rows: [CommitListRow] = []
    /// Each commit's row.
    private(set) var rowOfCommit: [Int] = []

    init() {}

    init(_ commits: [CommitInfo], grouped: Bool) {
        rows.reserveCapacity(commits.count + (grouped ? commits.count / 4 : 0))
        rowOfCommit.reserveCapacity(commits.count)
        guard grouped else {
            rows = commits.indices.map { .commit($0) }
            rowOfCommit = Array(commits.indices)
            return
        }
        for group in Self.groups(commits) {
            rows.append(.day(group.date, firstCommit: group.range.lowerBound))
            for index in group.range {
                rowOfCommit.append(rows.count)
                rows.append(.commit(index))
            }
        }
    }

    var count: Int { rows.count }

    func commitIndex(atRow row: Int) -> Int? {
        guard rows.indices.contains(row), case .commit(let index) = rows[row] else { return nil }
        return index
    }

    /// Consecutive commits from the same calendar day share a group. Calendar math runs only when the day changes,
    /// so 100k commits group in a few milliseconds.
    static func groups(_ commits: [CommitInfo], calendar: Calendar = .current) -> [CommitDayGroup] {
        var result: [CommitDayGroup] = []
        var dayStart = Date.distantFuture
        var dayEnd = Date.distantPast
        for (index, commit) in commits.enumerated() {
            let date = commit.committerDate
            if !result.isEmpty, date >= dayStart, date < dayEnd {
                result[result.count - 1].range = result[result.count - 1].range.lowerBound..<index + 1
                continue
            }
            dayStart = calendar.startOfDay(for: date)
            dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
            result.append(CommitDayGroup(id: commit.id, date: date, range: index..<index + 1))
        }
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
