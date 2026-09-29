// RepositorySwitcherTests.swift
// GroveTests
//
// The sidebar title's switcher lists bookmarks, the open one first, and switches on the same tab.

import Foundation
import Testing
@testable import Grove

@MainActor
struct RepositorySwitcherTests {

    private let myApp = "/Users/dev/Projects/my-app"
    private let apiServer = "/Users/dev/Projects/api-server"

    @Test func openRepositoryComesFirstThenMostRecent() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: apiServer))
        #expect(window.repositorySwitcherItems(matching: "").map(\.displayName)
                == ["api-server", "my-app", "blog", "dotfiles", "design-system"])
    }

    @Test func nameMatchesAtTheStartRankFirst() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: myApp))
        #expect(window.repositorySwitcherItems(matching: "a").map(\.displayName) == ["api-server", "my-app"])
        #expect(window.repositorySwitcherItems(matching: "SERVER").map(\.displayName) == ["api-server"])
        #expect(window.repositorySwitcherItems(matching: "nope").isEmpty)
    }

    @Test func switchingKeepsTheTabAndClosesTheSwitcher() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: myApp))
        window.loadSessionIfNeeded(for: RepositoryReference(path: myApp))
        let first = try await session(in: window, at: myApp)
        first.restoreSelection(.stashes)
        window.showRepositorySwitcher()

        let target = try #require(window.repositorySwitcherItems(matching: "api").first)
        window.switchRepository(to: target)
        #expect(!window.isShowingRepositorySwitcher)
        #expect(window.openRepo?.path == apiServer)
        #expect(window.sessions[myApp]?.session.isActive == false)

        window.loadSessionIfNeeded(for: RepositoryReference(path: apiServer))
        let second = try await session(in: window, at: apiServer)
        #expect(second.selectedItem == .stashes)
    }

    @Test func switcherOnlyOpensInsideARepository() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        #expect(window.handleBrowserAction(.switchRepository))
        #expect(!window.isShowingRepositorySwitcher)
    }

    private func session(in window: WindowViewModel, at path: String) async throws -> RepositorySession {
        for _ in 0..<50 {
            if let loaded = window.sessions[path] { return loaded.session }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
    }
}
