// RepositoryLinkParserTests.swift
// GroveTests

import Testing
@testable import Grove

struct RepositoryLinkParserTests {

    @Test func worktreeListParsesMainLinkedPrunableAndLocked() {
        let output = """
        worktree /repo
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /wt/feature
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/douwe/feature

        worktree /wt/gone
        HEAD 3333333333333333333333333333333333333333
        detached
        prunable gitdir file points to non-existent location

        worktree /wt/locked
        HEAD 4444444444444444444444444444444444444444
        branch refs/heads/locked
        locked on usb drive

        """
        let worktrees = WorktreeParser.parse(output)
        #expect(worktrees.map(\.path) == ["/repo", "/wt/feature", "/wt/gone", "/wt/locked"])
        #expect(worktrees.map(\.isMain) == [true, false, false, false])
        #expect(worktrees[1].branch == "douwe/feature")
        #expect(worktrees[2].branch == nil && worktrees[2].isPrunable)
        #expect(worktrees[3].isLocked && !worktrees[3].isPrunable)
    }

    @Test func submodulesJoinGitmodulesWithStatus() {
        let gitmodules = """
        [submodule "TopShelf"]
        \tpath = apps/ios/TopShelf
        \turl = https://github.com/example/topshelf.git
        [submodule "media"]
        \tpath = vendor/media
        \turl = git@github.com:example/media.git
        [submodule "ffmpeg"]
        \tpath = vendor/ffmpeg
        \turl = https://github.com/example/ffmpeg.git
        [submodule "icons"]
        \tpath = vendor/icons
        \turl = https://github.com/example/icons.git
        """
        let status = """
         bff0cbfb3aea91080244a018ca0249a44dc6e3bc apps/ios/TopShelf (1.1.0-1-gbff0cbf)
        +896815de7914c46307e474fac1f10ea8e31842f2 vendor/media (v1.9.0.0)
        -e101f77b10ae49f2c4c59ebea2a3201490509857 vendor/ffmpeg
        U0000000000000000000000000000000000000000 vendor/icons
        """
        let submodules = SubmoduleParser.parse(gitmodules: gitmodules, status: status)
        #expect(submodules.map(\.path) == ["apps/ios/TopShelf", "vendor/media", "vendor/ffmpeg", "vendor/icons"])
        #expect(submodules.map(\.state) == [.upToDate, .modified, .uninitialized, .conflicted])
        #expect(submodules[0].displayName == "TopShelf")
        #expect(submodules[0].shortSHA == "bff0cbf")
        #expect(submodules[1].url == "git@github.com:example/media.git")
    }

    @Test func submoduleMissingFromStatusCountsAsUninitialized() {
        let gitmodules = "[submodule \"lib\"]\n\tpath = lib\n\turl = https://example.com/lib.git\n"
        #expect(SubmoduleParser.parse(gitmodules: gitmodules, status: "").first?.state == .uninitialized)
    }
}
