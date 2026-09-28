// GroveBenchmarks.swift
// GroveTests
//
// Times real Grove load paths against generated fixtures. Opt-in: run tools/fixtures/bench.sh (GROVE_BENCH=1).

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized, .enabled(if: BenchmarkConfig.isEnabled, "Set GROVE_BENCH=1 (tools/fixtures/bench.sh)"))
struct GroveBenchmarks {

    private let report = BenchmarkReport.shared

    @Test func small() async throws { try await run(.small) }
    @Test func medium() async throws { try await run(.medium) }
    @Test func large() async throws { try await run(.large) }

    private func run(_ preset: FixturePreset) async throws {
        guard BenchmarkConfig.presets.contains(preset) else { return }
        // Grove inherits the environment; keep the user's global git config out of the numbers.
        setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
        let clean = try Fixture.cached(FixtureSpec(preset))
        let dirty = try Fixture.cached(FixtureSpec(preset, states: [.dirty(dirtyCount(preset))]))
        report.noteFixture(preset, "clean", clean)
        report.noteFixture(preset, "dirty", dirty)

        try await openAndSession(preset, clean.repo)
        try await history(preset, clean.repo)
        try await sidebarAndReview(preset, clean.repo)
        try await workingCopy(preset, dirty.repo)
        try await pullDialog(preset, clean.repo)
        try report.write()
    }

    private func dirtyCount(_ preset: FixturePreset) -> Int {
        switch preset {
        case .small: 20
        case .medium: 100
        case .large: 300
        }
    }

    // MARK: - Measurements

    private func openAndSession(_ preset: FixturePreset, _ path: URL) async throws {
        // Fixed cost every git call pays in Grove; puts the other numbers in perspective.
        let shell = GitShell(workingDirectory: path)
        try await report.measure(preset, "single git call (rev-parse HEAD)", setup: {}, body: {
            _ = try await shell.run(["rev-parse", "HEAD"])
        })
        // Same call from a background task; a large gap means git work is holding up the main actor.
        try await report.measure(preset, "single git call (off main)", setup: {}, body: {
            _ = try await Task.detached { try await shell.run(["rev-parse", "HEAD"]) }.value
        })
        try await report.measure(preset, "open repository", setup: {}, body: {
            _ = try await GitRepository(path: path)
        })
        try await report.measure(preset, "session start", setup: {
            RepositorySession(repository: try await GitRepository(path: path))
        }, body: { session in
            await session.start()
            session.stop()
        })
        try await report.measure(preset, "session refreshAll", setup: {
            let session = RepositorySession(repository: try await GitRepository(path: path))
            await session.start()
            session.stop()
            return session
        }, body: { session in
            await session.refreshAll()
        })
    }

    private func history(_ preset: FixturePreset, _ path: URL) async throws {
        let repository = try await GitRepository(path: path)
        try await report.measure(preset, "history loadInitial (main)", setup: {
            HistoryViewModel(repository: repository)
        }, body: { vm in
            await vm.loadInitial()
        })
        let branch = try await repository.localBranches().first { !$0.isHEAD && $0.upstream != nil }?.name ?? "main"
        try await report.measure(preset, "history loadInitial (branch)", setup: {
            let vm = HistoryViewModel(repository: repository)
            vm.filterBranch = branch
            return vm
        }, body: { vm in
            await vm.loadInitial()
        })

        let count = 10
        try await report.measure(preset, "select \(count) commits (cold)", setup: {
            try await loadedHistory(repository)
        }, body: { vm in
            try await select(vm.commits[1...count], in: vm)
        })
        try await report.measure(preset, "revisit \(count) commits (cached)", setup: {
            let vm = try await loadedHistory(repository)
            try await select(vm.commits[1...count], in: vm)
            return vm
        }, body: { vm in
            try await select(vm.commits[1...count], in: vm)
        })
    }

    private func sidebarAndReview(_ preset: FixturePreset, _ path: URL) async throws {
        let repository = try await GitRepository(path: path)
        try await report.measure(preset, "sidebar refresh", setup: {
            SidebarViewModel(repository: repository)
        }, body: { vm in
            await vm.refresh()
        })
        try await report.measure(preset, "branches review refresh (cold)", setup: {
            BranchesReviewViewModel(repository: repository)
        }, body: { vm in
            await vm.refresh()
        })
        try await report.measure(preset, "branches review refresh (warm)", setup: {
            let vm = BranchesReviewViewModel(repository: repository)
            await vm.refresh()
            return vm
        }, body: { vm in
            await vm.refresh()
        })
    }

    private func workingCopy(_ preset: FixturePreset, _ path: URL) async throws {
        let repository = try await GitRepository(path: path)
        try await report.measure(preset, "working copy refresh (dirty)", setup: {
            WorkingCopyViewModel(repository: repository)
        }, body: { vm in
            await vm.refresh()
            #expect(vm.errorMessage == nil)
        })
    }

    /// Mirrors PullDialogView's `.task`: strategy, remotes, then remote branches.
    /// The shared refs read, then what PullDialogView does on top of the refs a session already holds.
    private func pullDialog(_ preset: FixturePreset, _ path: URL) async throws {
        let repository = try await GitRepository(path: path)
        try await report.measure(preset, "refs read (RepositoryRefs.refresh)", setup: {
            RepositoryRefs(repository: repository, readsStatus: false)
        }, body: { refs in
            await refs.refresh()
        })
        try await report.measure(preset, "pull dialog load", setup: {
            let refs = RepositoryRefs(repository: repository, readsStatus: false)
            await refs.refresh()
            return refs
        }, body: { refs in
            _ = PullSourcePicker.defaultSource(for: repository.currentBranch, in: refs.remoteBranches)
            _ = await repository.defaultPullStrategy()
        })
    }

    // MARK: - Helpers

    /// Loaded and settled, so the timed part only sees its own work.
    private func loadedHistory(_ repository: GitRepository) async throws -> HistoryViewModel {
        let vm = HistoryViewModel(repository: repository)
        await vm.loadInitial()
        try await waitForDiff(vm)
        #expect(vm.commits.count > 20)
        return vm
    }

    private func select(_ commits: ArraySlice<CommitInfo>, in vm: HistoryViewModel) async throws {
        for commit in commits {
            vm.select(commit)
            try await waitForDiff(vm)
        }
    }

    /// `select` loads details in a task; the user sees the commit once its diff is in.
    private func waitForDiff(_ vm: HistoryViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while vm.isLoadingDiff {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .microseconds(200))
        }
    }
}
