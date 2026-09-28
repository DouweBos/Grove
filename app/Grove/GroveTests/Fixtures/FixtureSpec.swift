// FixtureSpec.swift
// GroveTests
//
// What a generated fixture repository contains. Foundation-only: also compiled into tools/fixtures' CLI.

import Foundation

enum FixturePreset: String, CaseIterable, Sendable {
    case small, medium, large
}

/// Repository states layered on top of the generated history.
enum FixtureState: Hashable, Sendable {
    case dirty(Int)
    case mergeConflict
    case rebaseConflict
    case detached
    case diverged
    case noUpstream
    case missingWorktree
    case stashes(Int)
    case largeFile
    case binaryImage

    var label: String {
        switch self {
        case .dirty(let count): "dirty\(count)"
        case .mergeConflict: "merge-conflict"
        case .rebaseConflict: "rebase-conflict"
        case .detached: "detached"
        case .diverged: "diverged"
        case .noUpstream: "no-upstream"
        case .missingWorktree: "missing-worktree"
        case .stashes(let count): "stashes\(count)"
        case .largeFile: "large-file"
        case .binaryImage: "binary-image"
        }
    }

    /// History-changing states run before the working-tree ones so dirt and conflicts survive.
    var order: Int {
        switch self {
        case .missingWorktree: 0
        case .diverged: 1
        case .noUpstream: 2
        case .largeFile: 3
        case .binaryImage: 4
        case .stashes: 5
        case .detached: 6
        case .mergeConflict, .rebaseConflict: 7
        case .dirty: 8
        }
    }
}

struct FixtureSpec: Sendable {
    /// Bump when output for the same spec changes, so cached fixtures are regenerated.
    static let generatorVersion = 1

    var preset: FixturePreset
    var seed: UInt64 = 1
    var commits: Int
    /// Local branches, including main.
    var branches: Int
    var remoteBranches: Int
    var tags: Int
    var worktrees: Int
    var submodules: Int
    var files: Int
    var authors = 24
    var states: [FixtureState] = []
    /// History ends here; fixed so SHAs are reproducible.
    var endDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    init(_ preset: FixturePreset, seed: UInt64 = 1, states: [FixtureState] = []) {
        self.preset = preset
        self.seed = seed
        self.states = states
        switch preset {
        case .small:
            (commits, branches, remoteBranches, tags, worktrees, submodules, files) = (200, 6, 8, 10, 0, 0, 60)
        case .medium:
            (commits, branches, remoteBranches, tags, worktrees, submodules, files) = (2_000, 50, 80, 200, 2, 1, 600)
        case .large:
            // Modeled on react-native-client.
            (commits, branches, remoteBranches, tags, worktrees, submodules, files) = (10_000, 30, 700, 5_000, 7, 3, 3_000)
        }
    }

    var sortedStates: [FixtureState] { states.sorted { $0.order < $1.order } }

    func has(_ state: FixtureState) -> Bool { states.contains(state) }

    var dirtyCount: Int {
        states.reduce(0) { if case .dirty(let count) = $1 { return count } else { return $0 } }
    }

    var stashCount: Int {
        states.reduce(0) { if case .stashes(let count) = $1 { return count } else { return $0 } }
    }

    /// Stable directory name for caching: same key, same repository.
    var cacheKey: String {
        let counts = [commits, branches, remoteBranches, tags, worktrees, submodules, files, authors].map(String.init)
        let parts = [preset.rawValue, "s\(seed)", "g\(Self.generatorVersion)", counts.joined(separator: "-")]
            + states.map(\.label).sorted()
        return parts.joined(separator: "_")
    }

    func validate() throws {
        if has(.mergeConflict) && has(.rebaseConflict) {
            throw FixtureError.invalid("--merge-conflict and --rebase-conflict can't be combined")
        }
        if commits < 10 { throw FixtureError.invalid("--commits must be at least 10") }
        if files < 5 { throw FixtureError.invalid("--files must be at least 5") }
        if branches < 1 { throw FixtureError.invalid("--branches must be at least 1") }
    }
}

enum FixtureError: LocalizedError {
    case invalid(String)
    case git(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .git(let command, let status, let output): "git \(command) exited \(status): \(output)"
        }
    }
}
