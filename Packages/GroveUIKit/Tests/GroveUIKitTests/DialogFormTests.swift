// DialogFormTests.swift
// GroveUIKitTests
//
// What each dialog submits, option by option, and that a missing feature stops it before anything runs.

#if os(macOS)
import Foundation
import GroveKit
import Testing
@testable import GroveUIKit

@MainActor
final class SpyCommands: GitCommandPerforming {
    let features: GitFeatures
    private(set) var performed: [GitCommand] = []

    init(features: GitFeatures = .all) {
        self.features = features
    }

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
        performed.append(command)
    }
}

@MainActor
struct DialogFormTests {

    private let spy = SpyCommands()
    private let repository = MockGitRepository()
    private let local = MockData.branches.filter(\.isLocal)
    private var head: BranchInfo { local.first(where: \.isHEAD)! }
    private var topic: BranchInfo { local.first { $0.name == "feature/auth" }! }

    private func context(_ commands: any GitCommandPerforming) -> GitDialogContext {
        let refs = RepositoryRefs(repository: repository)
        refs.replace(localBranches: local, remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes)
        return GitDialogContext(repository: repository, refs: refs, commands: commands)
    }

    private func submit(_ form: some GitDialogForm) async throws -> [GitCommand] {
        let spy = SpyCommands()
        try await form.submit(in: context(spy), progress: nil)
        return spy.performed
    }

    @Test func fetchTakesOneRemoteOrAll() async throws {
        var form = GitFetchForm(remotes: MockData.remotes)
        #expect(form.allRemotes)
        #expect(try await submit(form) == [.fetch(remote: nil)])
        form.allRemotes = false
        form.remote = "upstream"
        #expect(try await submit(form) == [.fetch(remote: "upstream")])
    }

    @Test func pullFromTheUpstreamOrAnotherBranchWithEveryOption() async throws {
        var form = GitPullForm(branch: head, remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes,
                               strategy: .rebase)
        #expect(form.source == "origin/main")
        #expect(try await submit(form) == [.pull(remote: nil, branch: nil, strategy: .rebase, options: PullOptions())])
        form.source = "upstream/main"
        form.strategy = .fastForwardOnly
        form.options = PullOptions(verifySignatures: true, skipHooks: true)
        #expect(try await submit(form) == [.pull(remote: "upstream", branch: "main", strategy: .fastForwardOnly,
                                                 options: PullOptions(verifySignatures: true, skipHooks: true))])
        form.source = PullSourcePicker.localSource("develop")
        #expect(try await submit(form) == [.pull(remote: ".", branch: "develop", strategy: .fastForwardOnly,
                                                 options: PullOptions(verifySignatures: true, skipHooks: true))])
    }

    @Test func pullFromATypedBranchThatWasNeverFetched() async throws {
        var form = GitPullForm(branch: head, remoteBranches: [], remotes: MockData.remotes, strategy: .merge)
        form.source = "upstream/release/2.0"
        #expect(try await submit(form) == [.pull(remote: "upstream", branch: "release/2.0", strategy: .merge,
                                                 options: PullOptions())])
        form.source = "nowhere"
        #expect(form.commands.isEmpty)
    }

    @Test func autoStashStashesAroundThePullAndRebase() async throws {
        // The mock repository always has changes; a clean one runs `commands(stashed: false)`.
        var pull = GitPullForm(branch: head, remoteBranches: [], remotes: MockData.remotes, strategy: .merge)
        pull.autoStash = true
        let pullCommand = GitCommand.pull(remote: nil, branch: nil, strategy: .merge, options: PullOptions())
        #expect(try await submit(pull) == [
            .stash(message: GitPullForm.stashMessage, includeUntracked: true, keepIndex: false, paths: nil), pullCommand,
            .applyStash(index: 0, drop: true),
        ])
        #expect(pull.commands(stashed: false) == [pullCommand])
        var rebase = GitRebaseForm(candidates: ["develop"])
        rebase.autoStash = true
        #expect(try await submit(rebase) == [
            .stash(message: GitRebaseForm.stashMessage, includeUntracked: true, keepIndex: false, paths: nil),
            .rebase(onto: "develop"), .applyStash(index: 0, drop: true),
        ])
        rebase.autoStash = false
        #expect(try await submit(rebase) == [.rebase(onto: "develop")])
    }

    @Test func pushHeadOrAnotherBranchWithEveryOption() async throws {
        var form = GitPushForm(branch: head, isHead: true, remotes: MockData.remotes)
        #expect(form.remote == "origin" && form.target == "main" && !form.setUpstream)
        #expect(try await submit(form) == [.push(remote: "origin", branch: "main", forceWithLease: false, setUpstream: false,
                                                 options: PushOptions())])
        form.remote = "upstream"
        form.target = "review "
        form.setUpstream = true
        form.forceWithLease = true
        form.tags = .follow
        form.recurseSubmodules = .onDemand
        form.skipHooks = true
        let options = PushOptions(recurseSubmodules: .onDemand, skipHooks: true, tags: .follow)
        #expect(try await submit(form) == [.push(remote: "upstream", branch: "review", forceWithLease: true, setUpstream: true,
                                                 options: options)])
        var other = GitPushForm(branch: topic, isHead: false, remotes: MockData.remotes)
        other.tags = .all
        #expect(try await submit(other) == [.pushBranch("feature/auth", remote: "origin", as: "feature/auth", forceWithLease: false,
                                                        setUpstream: false, options: PushOptions(tags: .all))])
    }

    @Test func anUnpublishedBranchPublishes() {
        let fresh = local.first { $0.upstream == nil }!
        let form = GitPushForm(branch: fresh, isHead: false, remotes: MockData.remotes)
        #expect(form.setUpstream && form.upstream == nil && form.target == fresh.name)
    }

    @Test func syncUsesTheUpstreamsRemote() async throws {
        var form = GitSyncForm(branch: head, remotes: MockData.remotes, strategy: nil)
        #expect(try await submit(form) == [])
        form.strategy = .merge
        #expect(try await submit(form) == [.sync(remote: "origin", strategy: .merge)])
    }

    @Test func createBranchWithEveryOptionAndItsUndo() async throws {
        var form = GitCreateBranchForm(start: "develop", localBranches: local.map(\.name))
        #expect(form.parent == "develop" && form.commands.isEmpty)
        form.name = "feature/x "
        form.track = true
        form.checkout = false
        form.pin = true
        let undo = GitUndoManager()
        var pinned: [String] = []
        var context = context(spy)
        context.undo = undo
        context.pinBranch = { pinned.append($0) }
        try await form.submit(in: context, progress: nil)
        #expect(spy.performed == [.createBranch(name: "feature/x", from: "develop", checkout: false, track: true, parent: "develop")])
        #expect(pinned == ["feature/x"] && undo.canUndo)
        form.name = "bad name"
        #expect(form.commands.isEmpty)
    }

    @Test func renameAnyBranchOrTheCurrentOne() async throws {
        var form = GitRenameBranchForm(branch: "develop", current: "main")
        #expect(form.commands.isEmpty, "unchanged")
        form.name = "trunk"
        #expect(try await submit(form) == [.renameBranch(from: "develop", to: "trunk")])
        var current = GitRenameBranchForm(branch: nil, current: "main")
        current.name = "session-x"
        #expect(try await submit(current) == [.renameCurrentBranch(to: "session-x")])
    }

    @Test func deleteForcedWithItsRemoteBranch() async throws {
        var form = GitDeleteBranchForm(branch: topic)
        #expect(try await submit(form) == [.deleteBranch(name: "feature/auth", force: false)])
        form.force = true
        form.deleteRemote = true
        #expect(try await submit(form) == [.deleteBranch(name: "feature/auth", force: true),
                                           .deleteRemoteBranch(name: "feature/auth", remote: "origin")])
    }

    @Test func deletingThroughItsWorktreeLeavesTheBranchToIt() async throws {
        let worktree = WorktreeInfo(path: "/tmp/wt", branch: "feature/auth", headSHA: "a", isMain: false, isPrunable: false, isLocked: false)
        var removed: [(String, Bool, String, Bool)] = []
        var context = context(spy)
        context.worktrees = GitDialogWorktrees(checkingOut: { _ in worktree },
                                               remove: { removed.append(($0.path, $1, $2.name, $3)) }, open: { _ in })
        var form = GitDeleteBranchForm(branch: topic)
        form.removeWorktree = true
        form.discardWorktreeChanges = true
        try await form.submit(in: context, progress: nil)
        #expect(spy.performed.isEmpty)
        #expect(removed.count == 1 && removed[0].0 == "/tmp/wt" && removed[0].1 && removed[0].2 == "feature/auth" && !removed[0].3)
    }

    @Test func trackMergeAndRebase() async throws {
        var track = GitTrackForm(branch: topic, remoteBranches: ["origin/feature/auth"], remotes: MockData.remotes)
        #expect(track.commands.isEmpty, "already tracks it")
        track.upstream = "upstream/main"
        #expect(try await submit(track) == [.setUpstream(branch: "feature/auth", upstream: "upstream/main")])
        var merge = GitMergeForm(candidates: ["develop", "feature/auth"])
        merge.squash = true
        #expect(try await submit(merge) == [.merge("develop", squash: true)])
        #expect(try await submit(GitRebaseForm(candidates: ["feature/auth"])) == [.rebase(onto: "feature/auth")])
    }

    @Test func thePreferredBranchLeadsThePickers() {
        var context = context(spy)
        context.preferredBranch = "feature/auth"
        #expect(context.otherLocalBranches.first == "feature/auth")
        #expect(GitMergeForm(candidates: context.otherLocalBranches).branch == "feature/auth")
    }

    @Test func stashWithEveryOption() async throws {
        var form = GitStashForm()
        #expect(try await submit(form) == [.stash(message: nil, includeUntracked: true, keepIndex: false, paths: nil)])
        form = GitStashForm(paths: ["b", "a"])
        form.message = " wip "
        form.includeUntracked = false
        form.keepIndex = true
        #expect(try await submit(form) == [.stash(message: "wip", includeUntracked: false, keepIndex: true, paths: ["a", "b"])])
        form.paths = []
        #expect(form.commands.isEmpty)
    }

    @Test func snapshotStashBranchTagAndRemotes() async throws {
        var snapshot = GitSnapshotForm(branch: "main", date: Date(timeIntervalSince1970: 0))
        #expect(snapshot.message.hasPrefix("Snapshot of main, "))
        snapshot.includeUntracked = false
        #expect(try await submit(snapshot) == [.snapshot(message: snapshot.message, includeUntracked: false)])
        var stashBranch = GitStashBranchForm(index: 2)
        stashBranch.name = "saved"
        #expect(try await submit(stashBranch) == [.branchFromStash(index: 2, name: "saved")])
        var tag = GitTagForm(target: nil)
        tag.name = "v1"
        #expect(try await submit(tag) == [.createTag(name: "v1", at: nil, message: nil, sign: false)])
        tag = GitTagForm(target: "abc1234")
        tag.name = "v2"
        tag.message = "Release"
        #expect(tag.commands == [.createTag(name: "v2", at: "abc1234", message: nil, sign: false)], "a message needs Annotated")
        tag.annotated = true
        #expect(try await submit(tag) == [.createTag(name: "v2", at: "abc1234", message: "Release", sign: false)])
        var add = GitRemoteForm(remote: nil, existing: MockData.remotes)
        #expect(add.name.isEmpty, "origin is taken")
        add.name = "fork"
        add.url = " /tmp/fork.git "
        #expect(try await submit(add) == [.addRemote(name: "fork", url: "/tmp/fork.git")])
        add.name = "origin"
        #expect(add.nameProblem(existing: MockData.remotes) != nil)
        var edit = GitRemoteForm(remote: MockData.remotes[0], existing: MockData.remotes)
        #expect(edit.commands.isEmpty && edit.nameProblem(existing: MockData.remotes) == nil)
        edit.name = "mine"
        edit.url = "/tmp/mine.git"
        #expect(try await submit(edit) == [.renameRemote(from: "origin", to: "mine"), .setRemoteURL("/tmp/mine.git", remote: "mine")])
    }

    /// Every form with every option on, so each feature it can need shows up.
    private var everyForm: [any GitDialogForm] {
        var pull = GitPullForm(branch: head, remoteBranches: [], remotes: MockData.remotes, strategy: .merge)
        pull.options = PullOptions(verifySignatures: true, skipHooks: true)
        var push = GitPushForm(branch: head, isHead: true, remotes: MockData.remotes)
        push.recurseSubmodules = .check
        push.skipHooks = true
        var pushOther = GitPushForm(branch: topic, isHead: false, remotes: MockData.remotes)
        pushOther.skipHooks = true
        var create = GitCreateBranchForm(start: "main", localBranches: ["main"])
        create.name = "x"
        var rename = GitRenameBranchForm(branch: "develop", current: "main")
        rename.name = "y"
        var delete = GitDeleteBranchForm(branch: topic)
        delete.deleteRemote = true
        var track = GitTrackForm(branch: topic, remoteBranches: [], remotes: MockData.remotes)
        track.upstream = "upstream/main"
        var tag = GitTagForm(target: nil)
        tag.name = "v1"
        var remote = GitRemoteForm(remote: MockData.remotes[0], existing: MockData.remotes)
        remote.url = "/tmp/x"
        var stashBranch = GitStashBranchForm(index: 0)
        stashBranch.name = "z"
        return [GitFetchForm(remotes: MockData.remotes), pull, push, pushOther,
                GitSyncForm(branch: head, remotes: MockData.remotes, strategy: .merge), create, rename, delete, track,
                GitMergeForm(candidates: ["develop"]), GitRebaseForm(candidates: ["develop"]), GitStashForm(),
                GitSnapshotForm(branch: "main"), stashBranch, tag, remote]
    }

    @Test(arguments: GitFeature.allCases)
    func aMissingFeatureStopsEveryFormThatNeedsIt(_ feature: GitFeature) async {
        var features = GitFeatures.all
        features.remove([feature], reason: "Not here")
        for form in everyForm where form.commands.contains(where: { $0.requiredFeatures.contains(feature) }) {
            #expect(form.unsupportedReason(features) == "Not here", "\(form)")
            let spy = SpyCommands(features: features)
            await #expect(throws: GitFeatureError.self, "\(form)") { try await form.submit(in: context(spy), progress: nil) }
            #expect(spy.performed.isEmpty, "\(form)")
        }
    }

    @Test func everyFormIsSupportedByDefault() {
        for form in everyForm {
            #expect(!form.commands.isEmpty && form.unsupportedReason(.all) == nil, "\(form)")
        }
    }
}
#endif
