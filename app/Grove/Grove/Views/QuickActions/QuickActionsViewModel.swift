// Views/QuickActions/QuickActionsViewModel.swift
// Grove

import AppKit
import Foundation
import Observation

enum QuickActionsTab: String, CaseIterable, Identifiable {
    case items = "Actions & Refs"
    case files = "Files"
    var id: String { rawValue }
}

/// What activating a palette row does.
enum QuickActionTarget {
    case navigate(SidebarItem)
    case command(GroveAction)
    case commit(CommitInfo)
    case blame(String)
    case openInTerminal
    case openInEditor
    case revealInFinder
}

struct QuickActionResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let kind: String
    let target: QuickActionTarget
}

@MainActor
@Observable
final class QuickActionsViewModel {

    private(set) var isPresented = false
    private(set) var searchText = ""
    private(set) var selectedTab: QuickActionsTab = .items
    private(set) var results: [QuickActionResult] = []
    private(set) var selectedIndex = 0
    var errorMessage: String?

    private var itemCandidates: [QuickActionResult] = []
    private var fileCandidates: [QuickActionResult] = []

    let session: RepositorySession
    private var repository: any GitRepositoryProtocol { session.repository }

    init(session: RepositorySession) {
        self.session = session
        itemCandidates = Self.staticItems
    }

    // MARK: - Presentation

    func toggle() {
        isPresented ? close() : open()
    }

    func open() {
        searchText = ""
        selectedIndex = 0
        isPresented = true
        updateResults()
        Task { await loadCandidates() }
    }

    func close() {
        isPresented = false
    }

    func setSearchText(_ text: String) {
        searchText = text
        selectedIndex = 0
        updateResults()
    }

    func selectTab(_ tab: QuickActionsTab) {
        selectedTab = tab
        selectedIndex = 0
        updateResults()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    func highlight(_ index: Int) {
        selectedIndex = index
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Activation

    /// Runs the highlighted row. `alternate` (Cmd+Return) opens files in the editor instead of Blame.
    func activateSelected(alternate: Bool = false) {
        guard results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        close()
        perform(result.target, alternate: alternate)
    }

    private func perform(_ target: QuickActionTarget, alternate: Bool) {
        do {
            switch target {
            case .navigate(let item):
                session.sidebarVM.select(item)
            case .command(let action):
                session.handleAction(action)
            case .commit(let commit):
                session.sidebarVM.select(.history)
                Task { await session.historyVM.selectCommit(id: commit.id) }
            case .blame(let path) where alternate:
                try ExternalToolLauncher.openInEditor([repository.path.appendingPathComponent(path)])
            case .blame(let path):
                session.sidebarVM.select(.blame)
                Task { await session.blameVM.open(file: path) }
            case .openInTerminal:
                try ExternalToolLauncher.openInTerminal(repository.path)
            case .openInEditor:
                try ExternalToolLauncher.openInEditor([repository.path])
            case .revealInFinder:
                NSWorkspace.shared.activateFileViewerSelecting([repository.path])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Data

    private func loadCandidates() async {
        async let local = try? repository.localBranches()
        async let remote = try? repository.remoteBranches()
        async let tags = try? repository.tags()
        async let commits = try? repository.log(maxCount: 200, skip: 0, branch: nil)
        async let files = try? repository.listTrackedFiles()
        let (localBranches, remoteBranches, tagList, commitList, fileList) = await (local, remote, tags, commits, files)

        var items = Self.staticItems
        items += (localBranches ?? []).map {
            QuickActionResult(id: "branch-\($0.id)", title: $0.name, subtitle: $0.isHEAD ? "current branch" : $0.upstream,
                              symbol: "arrow.triangle.branch", kind: "Branch", target: .navigate(.branch($0)))
        }
        items += (remoteBranches ?? []).map {
            QuickActionResult(id: "remote-\($0.id)", title: $0.name, subtitle: nil, symbol: "cloud",
                              kind: "Remote", target: .navigate(.remoteBranch($0)))
        }
        items += (tagList ?? []).map {
            QuickActionResult(id: "tag-\($0.id)", title: $0.name, subtitle: String($0.targetSHA.prefix(7)), symbol: "tag",
                              kind: "Tag", target: .navigate(.tag($0)))
        }
        items += (commitList ?? []).map {
            QuickActionResult(id: "commit-\($0.id)", title: $0.summary, subtitle: "\($0.shortSHA) \u{00B7} \($0.authorName)",
                              symbol: "smallcircle.filled.circle", kind: "Commit", target: .commit($0))
        }
        itemCandidates = items
        fileCandidates = (fileList ?? []).map {
            QuickActionResult(id: "file-\($0)", title: ($0 as NSString).lastPathComponent, subtitle: $0, symbol: "doc.text",
                              kind: "File", target: .blame($0))
        }
        updateResults()
    }

    private func updateResults() {
        let candidates = selectedTab == .items ? itemCandidates : fileCandidates
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let limit = 200
        guard !query.isEmpty else {
            results = Array(candidates.prefix(limit))
            return clampSelection()
        }
        // Title prefix matches first, then any title/subtitle match.
        let matches = candidates.filter {
            $0.title.lowercased().contains(query) || ($0.subtitle?.lowercased().contains(query) ?? false)
        }
        let prefixed = matches.filter { $0.title.lowercased().hasPrefix(query) }
        let rest = matches.filter { !$0.title.lowercased().hasPrefix(query) }
        results = Array((prefixed + rest).prefix(limit))
        clampSelection()
    }

    private func clampSelection() {
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
    }

    private static let staticItems: [QuickActionResult] = {
        func command(_ title: String, _ symbol: String, _ action: GroveAction) -> QuickActionResult {
            QuickActionResult(id: "cmd-\(title)", title: title, subtitle: nil, symbol: symbol, kind: "Command", target: .command(action))
        }
        func view(_ title: String, _ symbol: String, _ item: SidebarItem) -> QuickActionResult {
            QuickActionResult(id: "nav-\(title)", title: title, subtitle: nil, symbol: symbol, kind: "View", target: .navigate(item))
        }
        func tool(_ title: String, _ symbol: String, _ target: QuickActionTarget) -> QuickActionResult {
            QuickActionResult(id: "tool-\(title)", title: title, subtitle: nil, symbol: symbol, kind: "Open", target: target)
        }
        return [
            command("Fetch\u{2026}", "arrow.down.circle", .fetch),
            command("Pull\u{2026}", "arrow.down.to.line", .pull),
            command("Push\u{2026}", "arrow.up.to.line", .push),
            command("New Branch\u{2026}", "plus.square.on.square", .newBranch),
            command("Stash Changes\u{2026}", "tray.and.arrow.down", .stash),
            command("Merge\u{2026}", "arrow.triangle.merge", .merge),
            command("Rebase\u{2026}", "arrow.triangle.2.circlepath", .rebase),
            view("Changes", "tray", .workingCopy),
            view("History", "clock", .history),
            view("Stashes", "tray.2", .stashes),
            view("Pull Requests", "arrow.triangle.pull", .pullRequests),
            view("Reflog", "clock.arrow.circlepath", .reflog),
            view("Branches Review", "checklist", .branchesReview),
            view("Blame", "text.line.first.and.arrowtriangle.forward", .blame),
            view("Repository Settings", "gearshape", .settings),
            tool("Open in Terminal", "terminal", .openInTerminal),
            tool("Open in Editor", "chevron.left.forwardslash.chevron.right", .openInEditor),
            tool("Reveal in Finder", "folder", .revealInFinder)
        ]
    }()
}
