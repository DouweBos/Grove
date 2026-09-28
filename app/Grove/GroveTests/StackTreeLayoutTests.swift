// StackTreeLayoutTests.swift
// GroveTests

import Foundation
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
}
