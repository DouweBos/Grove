// StackTreeLayoutTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct StackTreeLayoutTests {

    @Test func linearStackStaysInOneLaneTipsFirst() {
        let layout = StackTreeLayout(MockData.linearStack)
        #expect(layout.laneCount == 1)
        #expect(layout.rows.map(\.branch) == MockData.linearStack.layers.reversed().map(\.branch))
        #expect(layout.rows.first?.segments == [.bottom(0)])
        #expect(layout.rows.last?.segments == [.top(0), .bottom(0)])
        #expect(layout.trunkLanes == [0])
    }

    @Test func splitOpensASecondLaneThatJoinsItsParent() {
        let layout = StackTreeLayout(MockData.splitStack)
        #expect(layout.laneCount == 2)
        #expect(layout.rows.map(\.branch) == ["auth-docs", "auth-ui-tests", "auth-ui", "auth-api"])
        #expect(layout.rows.map(\.lane) == [1, 0, 0, 0])
        #expect(layout.rows[1].segments.contains(.through(1)))
        #expect(layout.rows[2].segments.contains(.join(from: 1, to: 0)))
        #expect(layout.rows[2].segments.contains(.top(0)))
    }

    @Test func longestLineKeepsTheLeftLaneWhateverItsName() {
        func layer(_ branch: String, _ parent: String?) -> StackLayer {
            StackLayer(branch: branch, tipSHA: branch, parent: parent, base: "b", commits: [branch], health: [],
                       ahead: 0, behind: 0, hasUpstream: true, isHEAD: false, depth: 0)
        }
        // "a-side" sorts before "b-main" but "b-main" carries the longer line.
        let stack = BranchStack(name: "s", trunk: "main", layers: [
            layer("root", nil), layer("a-side", "root"), layer("b-main", "root"), layer("b-next", "b-main")
        ])
        let lanes = Dictionary(uniqueKeysWithValues: StackTreeLayout(stack).rows.map { ($0.branch, $0.lane) })
        #expect(lanes == ["root": 0, "a-side": 1, "b-main": 0, "b-next": 0])
    }
}
