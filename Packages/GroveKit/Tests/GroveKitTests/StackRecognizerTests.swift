// StackRecognizerTests.swift
// GroveKitTests
//
// Stack recognition over hand-built graphs shaped the way stacks get made: checkout -b chains, split commits,
// amended parents, squash merges.

import Foundation
import Testing
@testable import GroveKit

/// A commit graph built parents first, handed to the recognizer children first like rev-list's `--topo-order`.
private struct Graph {
    private var added: [(String, [String])] = []
    var tips: [String: String] = [:]
    var upstreams: Set<String> = []
    var head: String?

    mutating func commits(_ ids: [String], on parent: String) {
        var previous = parent
        for id in ids {
            added.append((id, [previous]))
            previous = id
        }
    }

    mutating func branch(_ name: String, at sha: String) { tips[name] = sha }

    var stackGraph: StackGraph {
        var graph = StackGraph()
        for (id, parents) in added.reversed() {
            graph.order.append(id)
            graph.parents[id] = parents
        }
        return graph
    }

    var branches: [BranchInfo] {
        tips.map { name, sha in
            BranchInfo(id: "refs/heads/\(name)", name: name, isLocal: true, isRemote: false, isHEAD: name == head,
                       targetSHA: sha, remoteName: nil, upstream: upstreams.contains(name) ? "refs/remotes/origin/\(name)" : nil,
                       ahead: 0, behind: 0)
        } + [BranchInfo(id: "refs/heads/main", name: "main", isLocal: true, isRemote: false, isHEAD: head == "main",
                        targetSHA: "t0", remoteName: nil, upstream: nil, ahead: 0, behind: 0)]
    }

    func input(formerTips: [String: Set<String>] = [:], patchIDs: [String: String] = [:],
               open: [BranchPullRequest] = [], merged: [BranchPullRequest] = [], worktrees: [WorktreeInfo] = []) -> StackRecognizerInput {
        StackRecognizerInput(trunk: "main", branches: branches, graph: stackGraph, formerTips: formerTips, patchIDs: patchIDs,
                             openPullRequests: BranchPullRequest.index(open), mergedPullRequests: merged,
                             pullRequestsLoaded: !open.isEmpty || !merged.isEmpty, worktrees: worktrees, currentPath: "/repo")
    }
}

private func pr(_ number: Int, _ head: String, base: String = "main", state: PRState = .open, sha: String? = nil) -> BranchPullRequest {
    BranchPullRequest(number: number, title: head, headBranch: head, isDraft: true, url: "", baseBranch: base, isMerged: state == .merged, headSHA: sha)
}

/// SHAs long enough for `headMatches`.
private func sha(_ name: String) -> String { name.padding(toLength: 40, withPad: "0", startingAt: 0) }

@MainActor
struct StackRecognizerTests {

    @Test func checkoutChainIsOneLinearStack() {
        var graph = Graph()
        graph.commits(["a1", "a2"], on: "t0")
        graph.commits(["b1"], on: "a2")
        graph.commits(["c1", "c2"], on: "b1")
        graph.branch("sam/onboarding-18-welcome", at: "a2")
        graph.branch("sam/onboarding-19-sign-in", at: "b1")
        graph.branch("sam/onboarding-20-profile", at: "c2")
        let result = StackRecognizer.recognize(graph.input())

        #expect(result.stacks.count == 1)
        let stack = result.stacks[0]
        #expect(stack.name == "onboarding")
        #expect(stack.layers.map(\.branch) == ["sam/onboarding-18-welcome", "sam/onboarding-19-sign-in", "sam/onboarding-20-profile"])
        #expect(stack.layers.map(\.parent) == [nil, "sam/onboarding-18-welcome", "sam/onboarding-19-sign-in"])
        #expect(stack.layers.map(\.commits.count) == [2, 1, 2])
        #expect(stack.layers.map(\.base) == ["t0", "a2", "b1"])
        #expect(stack.layers.map(\.depth) == [0, 1, 2])
        #expect(stack.layers.allSatisfy { !$0.health.contains(.needsRestack) })
        #expect(result.trunkBases[stack.id] == "t0")
    }

    @Test func oneCommitSplitIntoConsecutiveBranchesStacksLinearly() {
        var graph = Graph()
        graph.commits(["p1", "p2", "p3", "p4"], on: "t0")
        for (index, commit) in ["p1", "p2", "p3", "p4"].enumerated() { graph.branch("split/part-\(index + 1)", at: commit) }
        let stack = StackRecognizer.recognize(graph.input()).stacks[0]
        #expect(stack.layers.map(\.branch) == ["split/part-1", "split/part-2", "split/part-3", "split/part-4"])
        #expect(stack.layers.allSatisfy { $0.commits.count == 1 })
        #expect(stack.name == "part")
    }

    @Test func twoChildrenOnOneParentAreSiblings() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.commits(["b1"], on: "a1")
        graph.commits(["d1", "d2"], on: "a1")
        graph.branch("a", at: "a1")
        graph.branch("b", at: "b1")
        graph.branch("d", at: "d2")
        let stack = StackRecognizer.recognize(graph.input()).stacks[0]
        #expect(stack.layers.map(\.branch) == ["a", "b", "d"])
        #expect(stack.children(of: "a").map(\.branch) == ["b", "d"])
        #expect(stack.subtree(from: "a").count == 3)
        #expect(stack.layer("d")?.commits == ["d2", "d1"])
        #expect(stack.name == "a")
    }

    @Test func amendedParentFoundThroughItsReflog() {
        var graph = Graph()
        graph.commits(["a1", "a2"], on: "t0")
        graph.commits(["b1"], on: "a2")
        graph.commits(["a2x"], on: "a1")
        graph.branch("a", at: "a2x")
        graph.branch("b", at: "b1")
        let stack = StackRecognizer.recognize(graph.input(formerTips: ["a": ["a1", "a2"]])).stacks[0]
        let layer = stack.layer("b")
        #expect(layer?.parent == "a")
        #expect(layer?.base == "a2")
        #expect(layer?.commits == ["b1"])
        #expect(layer?.health.contains(.needsRestack) == true)
        #expect(stack.layer("a")?.health.contains(.needsRestack) == false)
    }

    @Test func parentThatAdvancedIsFoundThroughItsReflog() {
        var graph = Graph()
        graph.commits(["a1", "a2"], on: "t0")
        graph.commits(["c1"], on: "a1")
        graph.branch("a", at: "a2")
        graph.branch("c", at: "c1")
        // c was created at a1, which its own reflog leaves out; a was once at a1.
        let stack = StackRecognizer.recognize(graph.input(formerTips: ["a": ["a1", "a2"], "c": ["c1"]])).stacks[0]
        #expect(stack.layers.map(\.branch) == ["a", "c"])
        #expect(stack.layer("c")?.base == "a1")
        #expect(stack.layer("c")?.health.contains(.needsRestack) == true)
        #expect(stack.layer("a")?.parent == nil)
    }

    @Test func parentThatAdvancedStaysBelowOnceTheCommitsAreShared() {
        var graph = Graph()
        graph.commits(["p1", "p2", "p3"], on: "t0")
        graph.commits(["c1", "c2"], on: "p2")
        graph.branch("p", at: "p3")
        graph.branch("c", at: "c2")
        // c holds p's older commits themselves, not copies, so it sits above p whatever the patch-ids or names say.
        let ids = ["p1": "P1", "p2": "P2", "p3": "P3", "c1": "PC1", "c2": "PC2"]
        for formerTips in [[:], ["p": Set(["p2", "p3"])]] as [[String: Set<String>]] {
            let stack = StackRecognizer.recognize(graph.input(formerTips: formerTips, patchIDs: ids)).stacks[0]
            #expect(stack.layers.map(\.branch) == ["p", "c"])
            #expect(stack.layer("p")?.parent == nil)
            #expect(stack.layer("c")?.base == "p2")
            #expect(stack.layer("c")?.health.contains(.needsRestack) == true)
        }
    }

    @Test func forkWithoutEvidencePutsTheShorterSideBelow() {
        var graph = Graph()
        graph.commits(["a1", "a2x"], on: "t0")
        graph.commits(["a2", "b1"], on: "a1")
        graph.branch("a", at: "a2x")
        graph.branch("b", at: "b1")
        let stack = StackRecognizer.recognize(graph.input()).stacks[0]
        #expect(stack.layer("a")?.parent == nil)
        #expect(stack.layer("b")?.parent == "a")
        #expect(stack.layer("b")?.base == "a1")
    }

    @Test func amendedParentWithoutReflogFoundByPatchID() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.commits(["b1"], on: "a1")
        graph.commits(["a1x"], on: "t0")
        graph.branch("a", at: "a1x")
        graph.branch("b", at: "b1")
        let first = StackRecognizer.recognize(graph.input())
        #expect(first.stacks.isEmpty && first.wantsPatchIDs)

        let result = StackRecognizer.recognize(graph.input(patchIDs: ["a1": "P1", "a1x": "P1", "b1": "P2"]))
        let layer = result.stacks.first?.layer("b")
        #expect(layer?.parent == "a")
        #expect(layer?.base == "a1")
        #expect(layer?.commits == ["b1"])
        #expect(layer?.health.contains(.needsRestack) == true)
    }

    @Test func parentAmendedBelowItsTopKeepsOnlyTheChildsCommits() {
        var graph = Graph()
        graph.commits(["a1", "a2", "a3"], on: "t0")
        graph.commits(["b1"], on: "a3")
        graph.commits(["a3x"], on: "a2")
        graph.branch("a", at: "a3x")
        graph.branch("b", at: "b1")
        let layer = StackRecognizer.recognize(graph.input(patchIDs: ["a3": "P3", "a3x": "P3", "b1": "PB"])).stacks.first?.layer("b")
        #expect(layer?.parent == "a")
        #expect(layer?.base == "a3")
        #expect(layer?.commits == ["b1"])
    }

    @Test func squashMergedParentMarksTheChild() {
        var graph = Graph()
        graph.commits([sha("a1"), sha("a2")], on: "t0")
        graph.commits([sha("b1")], on: sha("a2"))
        graph.branch("b", at: sha("b1"))
        let merged = pr(10, "a", state: .merged, sha: sha("a2"))
        let stack = StackRecognizer.recognize(graph.input(open: [pr(11, "b", base: "a")], merged: [merged])).stacks.first
        let layer = stack?.layer("b")
        #expect(layer?.parent == "a")
        #expect(layer?.base == sha("a2"))
        #expect(layer?.commits == [sha("b1")])
        #expect(layer?.health.contains(.parentMerged) == true)
        #expect(layer?.mergedParent?.number == 10)
        #expect(stack?.roots.map(\.branch) == ["b"])
    }

    @Test func mergedParentStillLocalMarksTheChild() {
        var graph = Graph()
        graph.commits([sha("a1")], on: "t0")
        graph.commits([sha("b1")], on: sha("a1"))
        graph.branch("a", at: sha("a1"))
        graph.branch("b", at: sha("b1"))
        let stack = StackRecognizer.recognize(graph.input(open: [pr(11, "b", base: "a")],
                                                          merged: [pr(10, "a", state: .merged, sha: sha("a1"))])).stacks[0]
        #expect(stack.layer("b")?.health.contains(.parentMerged) == true)
        #expect(stack.layer("a")?.pullRequest?.isMerged == true)
        #expect(stack.layer("a")?.health.contains(.noPR) == false)
    }

    @Test func pullRequestBaseOrdersBranchesOnTheSameCommit() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.branch("lower", at: "a1")
        graph.branch("alpha", at: "a1")
        let stack = StackRecognizer.recognize(graph.input(open: [pr(2, "alpha", base: "lower"), pr(1, "lower")])).stacks[0]
        #expect(stack.layers.map(\.branch) == ["lower", "alpha"])
        #expect(stack.layer("alpha")?.commits.isEmpty == true)

        let byName = StackRecognizer.recognize(graph.input()).stacks[0]
        #expect(byName.layers.map(\.branch) == ["alpha", "lower"])
    }

    @Test func identicalPatchSetsAreFlaggedNotStacked() {
        var graph = Graph()
        graph.commits(["a1", "a2"], on: "t0")
        graph.commits(["c1", "c2"], on: "t0")
        graph.branch("feature", at: "a2")
        graph.branch("feature-copy", at: "c2")
        let result = StackRecognizer.recognize(graph.input(patchIDs: ["a1": "P1", "a2": "P2", "c1": "P1", "c2": "P2"],
                                                           open: [pr(5, "feature")]))
        #expect(result.stacks.isEmpty)
        #expect(result.duplicates == [DuplicateBranch(branch: "feature-copy", duplicateOf: "feature")])
    }

    @Test func layerInAnotherWorktreeNotesIt() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.commits(["d1"], on: "a1")
        graph.branch("a", at: "a1")
        graph.branch("d", at: "d1")
        graph.head = "a"
        let worktrees = [WorktreeInfo(path: "/repo", branch: "a", headSHA: "a1", isMain: true, isPrunable: false, isLocked: false),
                         WorktreeInfo(path: "/elsewhere", branch: "d", headSHA: "d1", isMain: false, isPrunable: false, isLocked: false)]
        let stack = StackRecognizer.recognize(graph.input(worktrees: worktrees)).stacks[0]
        #expect(stack.layer("d")?.worktreePath == "/elsewhere")
        #expect(stack.layer("a")?.worktreePath == nil)
        #expect(stack.layer("a")?.isHEAD == true)
    }

    @Test func healthReflectsUpstreamAndPullRequests() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.commits(["b1"], on: "a1")
        graph.branch("a", at: "a1")
        graph.branch("b", at: "b1")
        graph.upstreams = ["a"]
        let stack = StackRecognizer.recognize(graph.input(open: [pr(1, "a")])).stacks[0]
        #expect(stack.layer("a")?.health.isEmpty == true)
        #expect(stack.layer("b")?.health == [.unpushed, .noPR])
    }

    @Test func emptyBranchOnAMergedBranchIsNotAStack() {
        var graph = Graph()
        graph.commits([sha("a1")], on: "t0")
        graph.branch("leftover", at: sha("a1"))
        let result = StackRecognizer.recognize(graph.input(merged: [pr(10, "a", state: .merged, sha: sha("a1"))]))
        #expect(result.stacks.isEmpty)
    }

    @Test func loneBranchesAndMergedBranchesAreNotStacks() {
        var graph = Graph()
        graph.commits(["a1"], on: "t0")
        graph.commits(["x1"], on: "t0")
        graph.branch("a", at: "a1")
        graph.branch("x", at: "x1")
        graph.branch("merged", at: "t0")
        #expect(StackRecognizer.recognize(graph.input()).stacks.isEmpty)
    }

    @Test func stackNamesUseSharedWords() {
        #expect(StackRecognizer.stackName(["sam/onboarding-18-welcome", "sam/onboarding-19-sign-in"]) == "onboarding")
        #expect(StackRecognizer.stackName(["sam/one", "sam/two"]) == "one")
        #expect(StackRecognizer.stackName(["feature-1", "feature-2"]) == "feature")
        #expect(StackRecognizer.stackName(["a", "b"]) == "a")
        #expect(StackRecognizer.stackName(["auth", "auth-tests"]) == "auth")
    }
}

struct StackGitParsingTests {

    @Test func reflogTipsLeaveOutTheCreationEntry() {
        let zero = String(repeating: "0", count: 40)
        let (a, b, c) = (sha("a"), sha("b"), sha("c"))
        let text = """
        \(zero) \(a) Tester <t@example.com> 1700000000 +0000\tbranch: Created from HEAD
        \(a) \(b) Tester <t@example.com> 1700000001 +0000\tcommit: b
        \(b) \(c) Tester <t@example.com> 1700000002 +0000\tcommit (amend): c
        """
        #expect(GitRepository.parseReflogTips(text) == [b, c])
    }

    @Test func patchIDsKeyByCommit() {
        #expect(GitRepository.parsePatchIDs("p1 c1\np2 c2\n") == ["c1": "p1", "c2": "p2"])
        #expect(StackGraph.parse("c b\nb a\na\n").order == ["c", "b", "a"])
    }
}
