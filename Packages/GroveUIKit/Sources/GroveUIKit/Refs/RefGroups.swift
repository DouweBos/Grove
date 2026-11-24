// Refs/RefGroups.swift
// GroveUIKit
//
// How the sidebar lists branches: pinned and protected first, then flat names, then "prefix/" folders.

#if os(macOS)
import Foundation
import GroveKit

/// One folder of branches, or the flat ones when `prefix` is nil.
public nonisolated struct GitBranchGroup: Equatable {
    public let prefix: String?
    public let branches: [BranchInfo]
}

extension GitRefsModel {

    /// Local branches in Branches: not archived, not listed by the app, the base or trunk first, then folders.
    public func localBranchGroups(_ marks: GitBranchMarks = GitBranchMarks(), hiding hidden: Set<String> = []) -> [GitBranchGroup] {
        let branches = refs.localBranchesMatchingStacks.filter {
            !marks.archived.contains($0.name) && !hidden.contains($0.name) && !marks.protected.contains($0.name)
        }
        return Self.folderGroups(branches, trunk: marks.base ?? refs.trunk, name: \.name)
    }

    /// Protected branches, which lead Branches by their full name.
    func protectedBranches(_ marks: GitBranchMarks) -> [BranchInfo] {
        refs.localBranchesMatchingStacks.filter { marks.protected.contains($0.name) && !marks.archived.contains($0.name) }
    }

    /// Pinned branches, by name, also listed in their folder.
    func pinnedBranches(_ marks: GitBranchMarks) -> [BranchInfo] {
        refs.localBranchesMatchingStacks.filter { marks.pinned.contains($0.name) && !marks.archived.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Archived names with their branch, which may be gone.
    func archivedBranches(_ marks: GitBranchMarks) -> [(name: String, branch: BranchInfo?)] {
        marks.archived.sorted().map { name in (name, refs.localBranches.first { $0.name == name }) }
    }

    /// Branches the section counts: what Branches holds, pinned ones once.
    func listedBranchCount(_ marks: GitBranchMarks) -> Int {
        refs.localBranchesMatchingStacks.filter { !marks.archived.contains($0.name) }.count
    }

    /// One remote's branches, grouped by "/" in their name without the remote.
    public func remoteBranchGroups(of remote: RemoteInfo) -> [GitBranchGroup] {
        Self.folderGroups(remoteBranches(of: remote), trunk: refs.trunk) { RefActionsViewModel.shortName(of: $0) }
    }

    func remoteBranches(of remote: RemoteInfo) -> [BranchInfo] {
        refs.remoteBranches.filter { $0.remoteName == remote.name && !$0.name.hasSuffix("/HEAD") }
    }

    /// The trunk, then names without a "/", then a group per first path component, sorted.
    static func folderGroups(_ branches: [BranchInfo], trunk: String?, name: (BranchInfo) -> String) -> [GitBranchGroup] {
        var ungrouped: [BranchInfo] = []
        var groups: [String: [BranchInfo]] = [:]
        for branch in branches {
            let name = name(branch)
            if let slashIndex = name.firstIndex(of: "/") {
                groups[String(name[..<slashIndex]), default: []].append(branch)
            } else {
                ungrouped.append(branch)
            }
        }
        if let index = ungrouped.firstIndex(where: { name($0) == trunk }) {
            ungrouped.insert(ungrouped.remove(at: index), at: 0)
        }
        return [GitBranchGroup(prefix: nil, branches: ungrouped)]
            + groups.keys.sorted().map { GitBranchGroup(prefix: $0, branches: groups[$0]!) }
    }

    // MARK: Filter

    var isFiltering: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }

    func matches(_ name: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.localizedStandardContains(query)
    }
}
#endif
