import Foundation
import Testing

@testable import GroveKit

/// `move(fromOffsets:toOffset:)` must reorder exactly as SwiftUI's list move does.
@MainActor
struct RebasePlanMoveTests {
    private func planner() -> (InteractiveRebaseViewModel, [String]) {
        let commits = Array(MockData.commits.prefix(5))
        let vm = InteractiveRebaseViewModel(base: MockData.commits[5], commits: commits)
        return (vm, vm.steps.map(\.sha))
    }

    @Test func movesARowUp() {
        let (vm, s) = planner()
        vm.move(fromOffsets: [3], toOffset: 0)
        #expect(vm.steps.map(\.sha) == [s[3], s[0], s[1], s[2], s[4]])
    }

    @Test func movesARowDown() {
        let (vm, s) = planner()
        vm.move(fromOffsets: [0], toOffset: 3)
        #expect(vm.steps.map(\.sha) == [s[1], s[2], s[0], s[3], s[4]])
    }

    @Test func movesSeveralRowsToTheEnd() {
        let (vm, s) = planner()
        vm.move(fromOffsets: [0, 2], toOffset: 5)
        #expect(vm.steps.map(\.sha) == [s[1], s[3], s[4], s[0], s[2]])
    }

    @Test func movingOntoItselfChangesNothing() {
        let (vm, s) = planner()
        vm.move(fromOffsets: [2], toOffset: 2)
        #expect(vm.steps.map(\.sha) == s)
    }
}
