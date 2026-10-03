// Models/RepositorySnapshot.swift
// Grove

import Foundation
import GroveKit

/// What the browser's info panel shows about a repository, as last read.
struct RepositorySnapshot {
    let branch: BranchInfo?
    let changedCount: Int
    let remotes: [RemoteInfo]
    let commits: [CommitInfo]
}
