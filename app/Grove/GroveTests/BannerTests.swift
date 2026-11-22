// BannerTests.swift
// GroveTests
//
// A banner's trailing closure is its button's action when it has a button, and otherwise dismisses it.

import SwiftUI
import Testing
@testable import Grove

@MainActor
struct BannerTests {

    @Test func aTrailingClosureAfterAButtonTitleIsThatButtonsAction() {
        var retried = false
        let banner = Banner(symbol: "x", message: "Failed", actionTitle: "Retry") { retried = true }

        #expect(banner.onDismiss == nil)
        banner.action?()
        #expect(retried)
    }

    @Test func aTrailingClosureWithoutAButtonDismisses() {
        var dismissed = false
        let banner = Banner(symbol: "x", message: "Failed", tone: .negative) { dismissed = true }

        #expect(banner.action == nil)
        banner.onDismiss?()
        #expect(dismissed)
    }
}
