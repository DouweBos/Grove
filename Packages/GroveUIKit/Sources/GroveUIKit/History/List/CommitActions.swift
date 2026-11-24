// History/List/CommitActions.swift
// GroveUIKit
//
// What History does to commits, from its menus, keys and buttons, each checked against the repository's features.

#if os(macOS)
import AppKit
import GroveKit
import Observation
import UniformTypeIdentifiers

/// Two refs to compare in the kit's own sheet.
struct CompareRequest: Identifiable {
    let base: String
    let compare: String
    var id: String { "\(base)...\(compare)" }
}

/// What History has asked to show that isn't a view model action.
@MainActor
@Observable
final class HistoryPresenter {
    var checkout: CommitInfo?
    var compare: CompareRequest?
}

@MainActor
struct CommitActions {
    let viewModel: HistoryViewModel
    let features: GitFeatures
    let host: GitHistoryHost
    let uiHost: GitUIHost
    let presenter: HistoryPresenter

    // MARK: Checkout

    func checkoutProblem(_ commit: CommitInfo) -> String? {
        if let reason = features.unavailableReason(.checkout) { return reason }
        return commit.id == viewModel.headSHA ? "Already checked out" : nil
    }

    /// Asks first: HEAD detaches at the commit.
    func requestCheckout(_ commit: CommitInfo) {
        guard checkoutProblem(commit) == nil else { return NSSound.beep() }
        presenter.checkout = commit
    }

    // MARK: Elsewhere

    func compare(base: String, compare: String) {
        if let open = host.compare { open(base, compare) } else { presenter.compare = CompareRequest(base: base, compare: compare) }
    }

    func interactiveRebase(from commit: CommitInfo) {
        if let open = host.interactiveRebase { open(commit) } else { viewModel.request(.interactiveRebase(commit)) }
    }

    func copy(_ text: String, _ confirmation: String) {
        uiHost.copy(text)
        uiHost.toast(confirmation)
    }

    /// The selected commits' SHAs, newest first, one per line.
    func copySHAs() {
        let commits = viewModel.selectedCommits
        guard !commits.isEmpty else { return }
        copy(commits.map(\.id).joined(separator: "\n"), commits.count == 1 ? "Copied SHA" : "Copied \(commits.count) SHAs")
    }

    // MARK: Export

    func savePatch(_ commits: [CommitInfo]) async {
        guard features.contains(.export), viewModel.canSavePatch(commits),
              let url = await Self.chooseDestination(name: viewModel.patchFileName(for: commits),
                                                     message: "Save as a patch that git am can apply") else { return }
        await viewModel.savePatch(commits, to: url)
    }

    func exportArchive(_ commit: CommitInfo) async {
        guard features.contains(.export),
              let url = await Self.chooseDestination(name: viewModel.archiveFileName(for: commit),
                                                     message: "Export the files at \(commit.shortSHA) as a ZIP archive",
                                                     prompt: "Export", type: .zip) else { return }
        await viewModel.exportArchive(of: commit, to: url)
    }

    static func chooseDestination(name: String, message: String, prompt: String = "Save", type: UTType? = nil) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.message = message
        panel.prompt = prompt
        panel.canCreateDirectories = true
        if let type { panel.allowedContentTypes = [type] }
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    // MARK: Menu

    /// A commit's menu; `selected` is the multi-selection when the click was inside it.
    func fill(_ menu: NSMenu, commit: CommitInfo, selected: [CommitInfo]) {
        menu.autoenablesItems = false
        let short = "\u{201C}\(commit.shortSHA)\u{201D}"
        menu.addItem(ClosureMenuItem("Copy Commit SHA") { copy(commit.id, "Copied SHA") })
        menu.addItem(ClosureMenuItem("Copy Short SHA") { copy(commit.shortSHA, "Copied SHA") })
        menu.addItem(ClosureMenuItem("Copy Commit Message") { copy(commit.message, "Copied message") })
        menu.addItem(.separator())
        let patch = selected.count > 1 ? "Save \(selected.count) Commits as Patch" : "Save as Patch"
        menu.addItem(ClosureMenuItem(patch, problem: features.unavailableReason(.export)
                                     ?? (viewModel.canSavePatch(selected) ? nil : "Merges have no patch of their own")) {
            Task { await savePatch(selected) }
        })
        menu.addItem(ClosureMenuItem("Export as ZIP", problem: features.unavailableReason(.export)) {
            Task { await exportArchive(commit) }
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Check Out \(short)", problem: checkoutProblem(commit)) { requestCheckout(commit) })
        menu.addItem(ClosureMenuItem("Create Branch from \(short)", problem: features.unavailableReason(.createBranch)) {
            viewModel.request(.createBranch(commit))
        })
        menu.addItem(ClosureMenuItem("Create Tag at \(short)", problem: features.unavailableReason(.tag)) {
            viewModel.request(.createTag(commit))
        })
        menu.addItem(compareItem(commit))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Cherry-Pick \(short)",
                                     problem: commit.id == viewModel.headSHA ? "Already checked out" : nil) {
            Task { await viewModel.cherryPick(commit) }
        })
        menu.addItem(ClosureMenuItem("Revert \(short)") { viewModel.request(.revert(commit)) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Reset \(viewModel.headBranchName ?? "HEAD") to \(short)",
                                     problem: viewModel.canReset ? nil : "Only from the checked-out branch's history") {
            viewModel.request(.reset(commit))
        })
        menu.addItem(.separator())
        let rewrite = viewModel.canRewrite(commit) ? nil : "Only for commits on the checked-out branch, not merges"
        menu.addItem(ClosureMenuItem("Edit Commit Message", problem: rewrite) { viewModel.request(.reword(commit)) })
        if selected.count > 1 {
            menu.addItem(ClosureMenuItem("Squash \(selected.count) Commits",
                                         problem: viewModel.canSquash(selected) ? nil : "Pick an unbroken run of commits") {
                viewModel.request(.squashCommits(selected))
            })
        } else {
            menu.addItem(ClosureMenuItem("Squash with Parent", problem: viewModel.canSquashWithParent(commit) ? nil : rewrite
                                         ?? "The parent is a merge") {
                viewModel.request(.squash(commit))
            })
        }
        menu.addItem(ClosureMenuItem("Interactive Rebase from Here", problem: viewModel.canRebaseInteractively(onto: commit)
                                     ? nil : "Only below HEAD on its branch, with no merges above") {
            interactiveRebase(from: commit)
        })
        menu.addItem(ClosureMenuItem("Delete \(short)", problem: rewrite) { viewModel.request(.drop(commit)) })
    }

    /// With HEAD on the left; a branch at the commit can be compared by name.
    private func compareItem(_ commit: CommitInfo) -> NSMenuItem {
        let head = viewModel.headBranchName ?? "HEAD"
        let branches = viewModel.branches(at: commit).filter { !$0.isHEAD }
        guard !branches.isEmpty else {
            return ClosureMenuItem("Compare with HEAD") { compare(base: head, compare: commit.id) }
        }
        let item = NSMenuItem(title: "Compare with HEAD", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(ClosureMenuItem(commit.shortSHA) { compare(base: head, compare: commit.id) })
        for branch in branches {
            submenu.addItem(ClosureMenuItem(branch.name) { compare(base: head, compare: branch.name) })
        }
        item.submenu = submenu
        return item
    }
}
#endif
