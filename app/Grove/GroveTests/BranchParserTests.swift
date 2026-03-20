// BranchParserTests.swift
// GroveTests
//
// Tests for BranchParser — covers local branches, remote branches, HEAD
// detection, upstream tracking, ahead/behind counts, slash-in-name, and
// multiple branches.

import Foundation
import Testing
@testable import Grove

// MARK: - Helpers

/// Builds a single `git for-each-ref` output line in the format BranchParser expects.
/// Fields are NUL-separated; one line per branch.
private func makeBranchLine(
    refname: String,
    shortName: String,
    sha: String = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
    upstream: String = "",
    trackShort: String = "",
    head: String = ""
) -> String {
    [refname, shortName, sha, upstream, trackShort, head].joined(separator: "\0")
}

// MARK: - BranchParserTests

struct BranchParserTests {

    // MARK: Empty input

    @Test func branchParser_returnsEmptyForEmptyString() {
        let branches = BranchParser.parse("")
        #expect(branches.isEmpty)
    }

    // MARK: Local branch

    @Test func branchParser_parsesLocalBranch() {
        let line = makeBranchLine(
            refname: "refs/heads/main",
            shortName: "main"
        )
        let branches = BranchParser.parse(line)

        #expect(branches.count == 1)
        let branch = branches[0]
        #expect(branch.isLocal)
        #expect(!branch.isRemote)
        #expect(branch.name == "main")
        #expect(branch.id == "refs/heads/main")
    }

    @Test func branchParser_localBranch_isNotHEADByDefault() {
        let line = makeBranchLine(refname: "refs/heads/develop", shortName: "develop")
        let branches = BranchParser.parse(line)
        #expect(!branches[0].isHEAD)
    }

    // MARK: Current HEAD branch

    @Test func branchParser_parsesCurrentHEADBranch() {
        let line = makeBranchLine(
            refname: "refs/heads/main",
            shortName: "main",
            head: "*"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].isHEAD)
    }

    @Test func branchParser_nonHeadBranch_isHEADFalse() {
        let line = makeBranchLine(
            refname: "refs/heads/feature",
            shortName: "feature",
            head: ""
        )
        let branches = BranchParser.parse(line)
        #expect(!branches[0].isHEAD)
    }

    // MARK: Remote branch

    @Test func branchParser_parsesRemoteBranch() {
        let line = makeBranchLine(
            refname: "refs/remotes/origin/main",
            shortName: "origin/main"
        )
        let branches = BranchParser.parse(line)

        #expect(branches.count == 1)
        let branch = branches[0]
        #expect(branch.isRemote)
        #expect(!branch.isLocal)
        #expect(branch.remoteName == "origin")
    }

    @Test func branchParser_remoteWithSlashInBranchName_extractsRemoteName() {
        let line = makeBranchLine(
            refname: "refs/remotes/origin/feature/auth",
            shortName: "origin/feature/auth"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].remoteName == "origin")
    }

    @Test func branchParser_localBranch_remoteNameIsNil() {
        let line = makeBranchLine(refname: "refs/heads/main", shortName: "main")
        let branches = BranchParser.parse(line)
        #expect(branches[0].remoteName == nil)
    }

    // MARK: Branch with "/" in name (hierarchy)

    @Test func branchParser_parsesSlashNamedLocalBranch() {
        let line = makeBranchLine(
            refname: "refs/heads/feature/oauth2",
            shortName: "feature/oauth2"
        )
        let branches = BranchParser.parse(line)

        #expect(branches.count == 1)
        #expect(branches[0].name == "feature/oauth2")
        #expect(branches[0].isLocal)
    }

    // MARK: Upstream tracking

    @Test func branchParser_parsesUpstreamRef() {
        let line = makeBranchLine(
            refname: "refs/heads/main",
            shortName: "main",
            upstream: "refs/remotes/origin/main"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].upstream == "refs/remotes/origin/main")
    }

    @Test func branchParser_noUpstream_isNil() {
        let line = makeBranchLine(refname: "refs/heads/orphan", shortName: "orphan", upstream: "")
        let branches = BranchParser.parse(line)
        #expect(branches[0].upstream == nil)
    }

    // MARK: Ahead / Behind counts

    @Test func branchParser_parsesAheadCount() {
        let line = makeBranchLine(
            refname: "refs/heads/feature",
            shortName: "feature",
            upstream: "refs/remotes/origin/feature",
            trackShort: "[ahead 3]"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].ahead == 3)
        #expect(branches[0].behind == 0)
    }

    @Test func branchParser_parsesBehindCount() {
        let line = makeBranchLine(
            refname: "refs/heads/stale",
            shortName: "stale",
            upstream: "refs/remotes/origin/stale",
            trackShort: "[behind 5]"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].ahead == 0)
        #expect(branches[0].behind == 5)
    }

    @Test func branchParser_parsesAheadAndBehindCounts() {
        let line = makeBranchLine(
            refname: "refs/heads/diverged",
            shortName: "diverged",
            upstream: "refs/remotes/origin/diverged",
            trackShort: "[ahead 2, behind 7]"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].ahead == 2)
        #expect(branches[0].behind == 7)
    }

    @Test func branchParser_goneBranch_aheadBehindAreZero() {
        let line = makeBranchLine(
            refname: "refs/heads/deleted-remote",
            shortName: "deleted-remote",
            upstream: "refs/remotes/origin/gone",
            trackShort: "[gone]"
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].ahead == 0)
        #expect(branches[0].behind == 0)
    }

    @Test func branchParser_noTracking_aheadBehindAreZero() {
        let line = makeBranchLine(
            refname: "refs/heads/local-only",
            shortName: "local-only",
            trackShort: ""
        )
        let branches = BranchParser.parse(line)

        #expect(branches[0].ahead == 0)
        #expect(branches[0].behind == 0)
    }

    // MARK: Multiple branches

    @Test func branchParser_parsesMultipleBranches() {
        let output = [
            makeBranchLine(refname: "refs/heads/main", shortName: "main", head: "*"),
            makeBranchLine(refname: "refs/heads/develop", shortName: "develop"),
            makeBranchLine(refname: "refs/remotes/origin/main", shortName: "origin/main"),
        ].joined(separator: "\n")

        let branches = BranchParser.parse(output)

        #expect(branches.count == 3)

        let localBranches = branches.filter(\.isLocal)
        let remoteBranches = branches.filter(\.isRemote)
        #expect(localBranches.count == 2)
        #expect(remoteBranches.count == 1)

        let headBranch = branches.first(where: \.isHEAD)
        #expect(headBranch?.name == "main")
    }

    @Test func branchParser_multipleBranches_preserveOrder() {
        let names = ["main", "develop", "feature/auth", "bugfix/crash"]
        let output = names.map { name in
            makeBranchLine(refname: "refs/heads/\(name)", shortName: name)
        }.joined(separator: "\n")

        let parsed = BranchParser.parse(output)
        #expect(parsed.map(\.name) == names)
    }

    // MARK: Target SHA

    @Test func branchParser_storesSHA() {
        let sha = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let line = makeBranchLine(refname: "refs/heads/main", shortName: "main", sha: sha)
        let branches = BranchParser.parse(line)
        #expect(branches[0].targetSHA == sha)
    }

    // MARK: formatString

    @Test func branchParser_formatStringContainsExpectedPlaceholders() {
        let fmt = BranchParser.formatString
        #expect(fmt.contains("%(refname)"))
        #expect(fmt.contains("%(refname:short)"))
        #expect(fmt.contains("%(objectname)"))
        #expect(fmt.contains("%(upstream)"))
        #expect(fmt.contains("%(upstream:trackshort)"))
        #expect(fmt.contains("%(HEAD)"))
    }
}
