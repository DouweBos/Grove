// BranchTreeTests.swift
// GroveKitTests
//
// Branch folders split on `/`, and ref name validation.

import Foundation
import GroveKit
import Testing

private func branch(_ name: String) -> BranchInfo {
    BranchInfo(id: name, name: name, isLocal: true, isRemote: false, isHEAD: false, targetSHA: "abc", ahead: 0, behind: 0)
}

@MainActor
struct BranchTreeTests {

    @Test func nestsFoldersFirstThenBranches() {
        let tree = BranchTreeNode.build([branch("main"), branch("feature/ui/login"), branch("feature/api"), branch("dev")])
        #expect(tree.map(\.id) == ["feature", "dev", "main"])
        let feature = tree[0]
        #expect(feature.isFolder)
        #expect(feature.children.map(\.id) == ["feature/ui", "feature/api"])
        #expect(feature.children[0].children.map(\.branch?.name) == ["feature/ui/login"])
    }

    @Test func ancestorsRevealABranch() {
        #expect(BranchTreeNode.ancestors(of: "feature/ui/login") == ["feature", "feature/ui"])
        #expect(BranchTreeNode.ancestors(of: "main").isEmpty)
    }

    @Test func refNamesFollowGit() {
        #expect(RefName.isValid("feature/login"))
        for bad in ["", "-x", "a..b", "a b", "a.lock", "a/", "a@{1}", "a~1", "a//b"] {
            #expect(!RefName.isValid(bad), "\(bad)")
        }
    }
}
