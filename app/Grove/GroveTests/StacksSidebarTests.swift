// StacksSidebarTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

@MainActor
struct StacksSidebarTests {

    @Test func stackedBranchesLeaveTheBranchesList() {
        let vm = SidebarViewModel(repository: MockGitRepository())
        let other = BranchInfo(id: "refs/heads/solo", name: "solo", isLocal: true, isRemote: false, isHEAD: false,
                               targetSHA: "s", remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        vm.refs.replace(localBranches: MockData.stackBranches + [other], stacks: [MockData.linearStack, MockData.splitStack])

        let listed = vm.localBranchGroups.flatMap(\.branches).map(\.name)
        #expect(listed == ["solo"])
        #expect(vm.stackedBranchNames.count == 9)
        #expect(vm.stacks.map(\.name) == ["companion", "auth"])
    }

    @Test func splitStackSubtreesKeepTopologicalOrder() {
        let stack = MockData.splitStack
        #expect(stack.roots.map(\.branch) == ["auth-api"])
        #expect(stack.subtree(from: "auth-ui").map(\.branch) == ["auth-ui", "auth-ui-tests", "auth-docs"])
        #expect(stack.needsAttention)
    }
}
