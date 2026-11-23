// HistoryViewTests.swift
// GroveUIKitTests
//
// History, its menus and keys, Compare, File History and the rebase planner lay out and only offer what the
// repository supports.

#if os(macOS)
import AppKit
@testable import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
private final class HistorySpyCommands: GitCommandPerforming {
    let features: GitFeatures
    private(set) var performed: [GitCommand] = []

    init(features: GitFeatures = .all) { self.features = features }

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
        performed.append(command)
    }
}

@MainActor
@Suite(.serialized)
struct HistoryViewTests {

    private func render(_ view: some View, width: CGFloat, height: CGFloat = 700) -> (NSWindow, NSHostingView<AnyView>) {
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (window, hosting)
    }

    private func loaded() async -> HistoryViewModel {
        let repository = MockGitRepository()
        let vm = HistoryViewModel(repository: repository)
        await vm.loadInitial()
        return vm
    }

    private func table(in view: NSView) -> CommitNSTableView? {
        (view as? CommitNSTableView) ?? view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    private func actions(_ vm: HistoryViewModel, features: GitFeatures = .all, copied: @escaping (String) -> Void = { _ in })
        -> CommitActions {
        CommitActions(viewModel: vm, features: features, host: GitHistoryHost(),
                      uiHost: GitUIHost(copy: copied), presenter: HistoryPresenter())
    }

    @Test func historyLaysOutWideNarrowZoomedAndInBothLayouts() async throws {
        let vm = await loaded()
        let context = GitDialogContext(repository: vm.repository, refs: vm.refs, commands: HistorySpyCommands())
        var zoomed = GitUIStyle.system
        zoomed.fontScale = 1.4
        for layout in HistoryLayout.allCases {
            vm.setLayout(layout)
            for (width, style) in [(1100.0, GitUIStyle.system), (520.0, .system), (1100.0, zoomed)] {
                var host = GitHistoryHost()
                host.ownCommits = Set(vm.commits.prefix(2).map(\.id))
                host.title = "feature vs main"
                let (window, view) = render(GitHistoryView(viewModel: vm, dialogs: context, host: host).gitUIStyle(style), width: width)
                let table = try #require(table(in: view))
                #expect(table.numberOfRows >= vm.commits.count)
                #expect(table.selectedRowIndexes.count == 1)
                window.close()
            }
        }
        vm.setLayout(.graph)
    }

    @Test func zoomScalesTheRows() {
        var style = GitUIStyle.system
        style.fontScale = 17.0 / 13
        let metrics = CommitListMetrics(style)
        #expect(metrics.graphRowHeight == 60)
        #expect(metrics.tableRowHeight == 34)
        #expect(metrics.visibleLanes(30, width: 300) == 8)
        #expect(metrics.visibleLanes(30, width: 2000) > 8)
    }

    @Test func aWorktreeMenuOffersNoCheckoutBranchTagOrExport() async throws {
        let vm = await loaded()
        let commit = try #require(vm.commits.dropFirst().first)
        var features = GitFeatures.all
        features.remove([.checkout, .createBranch, .tag], reason: "Only in the project root")
        features.remove([.export], reason: "Only for repositories on this Mac")
        let menu = NSMenu()
        actions(vm, features: features).fill(menu, commit: commit, selected: [commit])
        let titles = Dictionary(menu.items.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
        for title in ["Check Out \u{201C}\(commit.shortSHA)\u{201D}", "Create Branch from \u{201C}\(commit.shortSHA)\u{201D}",
                      "Create Tag at \u{201C}\(commit.shortSHA)\u{201D}", "Save as Patch", "Export as ZIP"] {
            let item = try #require(titles[title], "\(title)")
            #expect(!item.isEnabled, "\(title)")
            #expect(item.toolTip != nil, "\(title)")
        }
        #expect(titles["Cherry-Pick \u{201C}\(commit.shortSHA)\u{201D}"]?.isEnabled == true)
        #expect(titles["Compare with HEAD"] != nil)
        #expect(!menu.items.contains { $0.title.hasSuffix("\u{2026}") })

        let full = NSMenu()
        actions(vm).fill(full, commit: commit, selected: [commit])
        #expect(full.items.first { $0.title.hasPrefix("Check Out") }?.isEnabled == true)
    }

    @Test func keysSelectAllCopyAndCheckOut() async throws {
        let vm = await loaded()
        var copied: [String] = []
        let context = GitDialogContext(repository: vm.repository, refs: vm.refs, commands: HistorySpyCommands())
        let (window, view) = render(
            GitHistoryView(viewModel: vm, dialogs: context).gitUIHost(GitUIHost(copy: { copied.append($0) })), width: 1100)
        defer { window.close() }
        let table = try #require(table(in: view))
        let coordinator = try #require(table.coordinator)
        table.keyDown(with: try key(.downArrow, shift: true))
        #expect(vm.selection.count == 2)
        table.selectAll(nil)
        #expect(vm.selection.count == vm.commits.count)
        table.copy(nil)
        #expect(copied.last == vm.commits.map(\.id).joined(separator: "\n"))

        coordinator.actions = actions(vm)
        vm.select(vm.commits[1])
        coordinator.activate()
        #expect(coordinator.actions?.presenter.checkout?.id == vm.commits[1].id)
        let presenter = try #require(coordinator.actions?.presenter)
        presenter.checkout = nil
        vm.select(vm.commits[0])
        coordinator.activate()
        // HEAD is already checked out.
        #expect(presenter.checkout == nil)
    }

    @Test func compareFileHistoryAndRebaseLayOut() async throws {
        let vm = await loaded()
        let context = GitDialogContext(repository: vm.repository, refs: vm.refs, commands: HistorySpyCommands())
        var base = "main"
        var compare = vm.commits[2].id
        let compareView = GitCompareView(context: context, base: Binding(get: { base }, set: { base = $0 }),
                                         compare: Binding(get: { compare }, set: { compare = $0 }))
        let fileHistory = vm.fileHistory(path: "Sources/App.swift")
        let rebase = GitInteractiveRebaseView(viewModel: vm, from: vm.commits[3].id) {}
        for view in [AnyView(compareView), AnyView(GitFileHistoryView(viewModel: fileHistory)), AnyView(rebase)] {
            let (window, hosting) = render(view, width: 1000)
            #expect(hosting.fittingSize.width > 0)
            window.close()
        }
    }

    private func key(_ special: NSEvent.SpecialKey, shift: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: String(Character(special.unicodeScalar)),
                                      charactersIgnoringModifiers: String(Character(special.unicodeScalar)), isARepeat: false,
                                      keyCode: special == .downArrow ? 125 : 126))
    }
}
#endif
