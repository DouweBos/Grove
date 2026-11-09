// Mocks/MockData+Stacks.swift
// GroveKit
//
// A linear stack and a split one, for previews of stacks in the sidebar and the Stack tab.

import Foundation

extension MockData {

    private static func sha(_ seed: String) -> String { seed.padding(toLength: 40, withPad: "0", startingAt: 0) }

    private static func layer(_ branch: String, parent: String?, commits: Int, depth: Int, health: Set<LayerHealth> = [],
                              pr: Int? = nil, isHEAD: Bool = false, ahead: Int = 0, worktree: String? = nil) -> StackLayer {
        let own = (0..<commits).map { sha("\(branch.count)\($0)c\(depth)") }
        return StackLayer(
            branch: branch, tipSHA: own.first ?? sha("tip\(depth)"), parent: parent, base: sha("base\(depth)"), commits: own,
            health: health,
            pullRequest: pr.map { BranchPullRequest(number: $0, title: branch, headBranch: branch, isDraft: true, url: "",
                                                    baseBranch: parent ?? "main", checks: $0 % 2 == 0 ? .passing : .failing) },
            mergedParent: health.contains(.parentMerged)
                ? BranchPullRequest(number: 6300, title: "Welcome", headBranch: parent ?? "", isDraft: false, url: "", isMerged: true)
                : nil,
            ahead: ahead, behind: 0, hasUpstream: pr != nil, isHEAD: isHEAD, worktreePath: worktree, depth: depth)
    }

    /// `18-welcome → 19-sign-in → 20-profile → 21-permissions → 22-tour`, 54 commits behind main.
    public static let linearStack = BranchStack(name: "onboarding", trunk: "main", layers: [
        layer("sam/onboarding-18-welcome", parent: nil, commits: 9, depth: 0, pr: 6329),
        layer("sam/onboarding-19-sign-in", parent: "sam/onboarding-18-welcome", commits: 3, depth: 1, pr: 6330, isHEAD: true),
        layer("sam/onboarding-20-profile", parent: "sam/onboarding-19-sign-in", commits: 7, depth: 2,
              health: [.needsRestack], pr: 6338),
        layer("sam/onboarding-21-permissions", parent: "sam/onboarding-20-profile", commits: 1, depth: 3, pr: 6443),
        layer("sam/onboarding-22-tour", parent: "sam/onboarding-21-permissions", commits: 2, depth: 4,
              health: [.noPR, .unpushed], ahead: 2, worktree: "/tmp/onboarding-tour")
    ], trunkAhead: 54)

    /// `a → b → c` plus `b → d`, with `a` merged.
    public static let splitStack = BranchStack(name: "auth", trunk: "main", layers: [
        layer("auth-api", parent: nil, commits: 2, depth: 0, pr: 12),
        layer("auth-ui", parent: "auth-api", commits: 3, depth: 1, pr: 13),
        layer("auth-ui-tests", parent: "auth-ui", commits: 1, depth: 2, health: [.needsRestack, .noPR, .unpushed]),
        layer("auth-docs", parent: "auth-ui", commits: 1, depth: 2, pr: 14)
    ], trunkAhead: 3)

    /// Local branches matching the stack fixtures' layers.
    public static let stackBranches: [BranchInfo] = (linearStack.layers + splitStack.layers).map { layer in
        BranchInfo(id: "refs/heads/\(layer.branch)", name: layer.branch, isLocal: true, isRemote: false, isHEAD: layer.isHEAD,
                   targetSHA: layer.tipSHA, remoteName: nil,
                   upstream: layer.hasUpstream ? "refs/remotes/origin/\(layer.branch)" : nil, ahead: layer.ahead, behind: 0)
    }
}
