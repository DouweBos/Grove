// Models/BranchTree.swift
// GroveKit

import Foundation

/// Branches as nested folders split on `/`: `feature/ui/login` sits in `feature` › `ui`.
public struct BranchTreeNode: Identifiable {
    /// The folder path (`feature/ui`) or the branch's full name.
    public let id: String
    public let title: String
    /// Nil for a folder.
    public let branch: BranchInfo?
    public private(set) var children: [BranchTreeNode]

    public var isFolder: Bool { branch == nil }

    /// The top level of the tree, folders first and then branches, each by name.
    public static func build(_ branches: [BranchInfo]) -> [BranchTreeNode] {
        var root = BranchTreeNode(id: "", title: "", branch: nil, children: [])
        for branch in branches {
            root.insert(branch, parts: branch.name.split(separator: "/").map(String.init)[...], prefix: "")
        }
        return root.sorted().children
    }

    /// Folder paths above `name`, e.g. to start with the checked-out branch revealed.
    public static func ancestors(of name: String) -> [String] {
        let parts = name.split(separator: "/").map(String.init)
        return parts.indices.dropLast().map { parts[...$0].joined(separator: "/") }
    }

    private mutating func insert(_ branch: BranchInfo, parts: ArraySlice<String>, prefix: String) {
        guard let first = parts.first else { return }
        let path = prefix.isEmpty ? first : "\(prefix)/\(first)"
        if parts.count == 1 {
            children.append(BranchTreeNode(id: branch.name, title: first, branch: branch, children: []))
            return
        }
        let index = children.firstIndex { $0.isFolder && $0.id == path } ?? {
            children.append(BranchTreeNode(id: path, title: first, branch: nil, children: []))
            return children.count - 1
        }()
        children[index].insert(branch, parts: parts.dropFirst(), prefix: path)
    }

    private func sorted() -> BranchTreeNode {
        var copy = self
        copy.children = children.map { $0.sorted() }.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return copy
    }
}
