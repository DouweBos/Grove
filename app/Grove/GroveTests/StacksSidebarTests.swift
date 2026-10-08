// StacksSidebarTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct StacksSidebarTests {

    @Test func stackedBranchesAreListedUnderTheirStack() {
        let vm = SidebarViewModel(repository: MockGitRepository())
        let other = BranchInfo(id: "refs/heads/solo", name: "solo", isLocal: true, isRemote: false, isHEAD: false,
                               targetSHA: "s", remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        vm.refs.replace(localBranches: MockData.stackBranches + [other], stacks: [MockData.linearStack, MockData.splitStack])

        let listed = vm.localBranchGroups.flatMap(\.branches).map(\.name)
        #expect(listed == ["solo"])
        #expect(vm.stackedBranchNames.count == 9)
        #expect(vm.stacks.map(\.name) == ["companion", "auth"])
    }

    @Test func stackRowsReadInStackOrderAndStartAtTheRoot() {
        let rows = StackSidebarLanes.rows(of: MockData.splitStack)
        #expect(rows.map(\.layer.branch) == ["auth-api", "auth-ui", "auth-ui-tests", "auth-docs"])
        #expect(Set(rows.map(\.lanes.laneCount)) == [2])
        #expect(rows.first?.lanes.segments == [.top(0)])
    }

    @Test func folderOpenedForHEADClosesWhenHEADLeaves() {
        var expansion = FolderExpansion(containsHEAD: true)
        expansion.headChanged(contains: false)
        #expect(!expansion.isExpanded)
        expansion.headChanged(contains: true)
        #expect(expansion.isExpanded)
    }

    @Test func folderTheUserToggledStaysAsLeft() {
        var opened = FolderExpansion(containsHEAD: false)
        opened.toggle(to: true)
        opened.headChanged(contains: true)
        opened.headChanged(contains: false)
        #expect(opened.isExpanded)

        var closed = FolderExpansion(containsHEAD: true)
        closed.toggle(to: false)
        closed.headChanged(contains: false)
        closed.toggle(to: true)
        closed.headChanged(contains: false)
        #expect(closed.isExpanded)
        #expect(!FolderExpansion(containsHEAD: false).isExpanded)
    }

    @Test func splitStackSubtreesKeepTopologicalOrder() {
        let stack = MockData.splitStack
        #expect(stack.roots.map(\.branch) == ["auth-api"])
        #expect(stack.subtree(from: "auth-ui").map(\.branch) == ["auth-ui", "auth-ui-tests", "auth-docs"])
        #expect(stack.needsAttention)
    }

    @Test func showingAStackSelectsItsFolder() {
        let vm = SidebarViewModel(repository: MockGitRepository())
        vm.refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.linearStack, MockData.splitStack])

        vm.showStack(containing: "auth-ui-tests")
        #expect(vm.selection == .branchStack(MockData.splitStack.id))
        #expect(RepositoryTab(item: .branchStack(MockData.splitStack.id)) == .stack)
    }

    @Test func switcherMatchesStackAndLayerNames() {
        let refs = RepositoryRefs(repository: MockGitRepository())
        refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.linearStack, MockData.splitStack])
        let vm = StackViewModel(repository: MockGitRepository(), refs: refs)

        #expect(vm.stacks(matching: "").count == 2)
        #expect(vm.stacks(matching: "AUTH").map(\.name) == ["auth"])
        #expect(vm.stacks(matching: "ui-tests").map(\.name) == ["auth"])
    }
}
