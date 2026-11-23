// DialogViewTests.swift
// GroveUIKitTests
//
// Every dialog lays out, with and without the features a host may lack, and the presenter says how each closed.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
@Suite(.serialized)
struct DialogViewTests {

    static let dialogs: [GitDialog] = {
        let topic = MockData.branches.first { $0.name == "feature/auth" }!
        return [.fetch, .pull, .push(), .push(branch: "develop"), .sync, .createBranch(), .createBranch(from: "abc1234"),
                .renameBranch("develop"), .renameCurrentBranch, .deleteBranch(topic), .trackRemoteBranch(topic), .merge, .rebase,
                .stash(), .stash(paths: ["README.md"]), .snapshot, .createTag(), .createTag(at: "abc1234"), .addRemote,
                .editRemote(MockData.remotes[0]), .branchFromStash(index: 1)]
    }()

    private func context(_ features: GitFeatures) -> GitDialogContext {
        let repository = MockGitRepository()
        let refs = RepositoryRefs(repository: repository)
        refs.replace(localBranches: MockData.branches.filter(\.isLocal), remoteBranches: MockData.branches.filter(\.isRemote),
                     remotes: MockData.remotes)
        return GitDialogContext(repository: repository, refs: refs, commands: SpyCommands(features: features))
    }

    @Test func everyDialogLaysOutWithAndWithoutTheHostsFeatures() {
        var host = GitFeatures.all
        host.remove([.skipHooks, .autostash, .cancel, .verifySignatures, .recurseSubmodules], reason: "Not on the host")
        var scaled = GitUIStyle.system
        scaled.fontScale = 1.3
        for features in [GitFeatures.all, host] {
            for dialog in Self.dialogs {
                let view = GitDialogView(dialog, context: context(features)).gitUIStyle(scaled)
                let size = NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 2000, height: 4000))
                #expect(size.width >= 420 * 1.3 && size.height > 120, "\(dialog.id)")
            }
        }
    }

    @Test func idsAndKindsTellDialogsApart() {
        #expect(Set(Self.dialogs.map(\.id)).count == Self.dialogs.count)
        #expect(GitDialog.renameCurrentBranch.kind == GitDialog.renameBranch("x").kind)
    }

    @Test func thePresenterReportsHowEachDialogClosed() {
        let presenter = GitDialogPresenter()
        var closed: [(String, Bool)] = []
        presenter.onClose = { closed.append(($0.kind, $1)) }
        presenter.present(.merge, context: context(.all))
        #expect(presenter.request?.dialog == .merge)
        presenter.present(.rebase, context: context(.all))
        presenter.dismiss()
        #expect(presenter.request == nil)
        #expect(closed.map(\.0) == ["merge", "rebase"] && closed.allSatisfy { !$0.1 })
    }
}
#endif
