// Models/RepositoryReference.swift
// Grove
//
// Lightweight identifier used to open a repository window.
// Passed via WindowGroup(for:) so it must be Codable and Hashable.

import Foundation

/// A lightweight, `Codable`/`Hashable` reference to a repository on disk.
///
/// Used as the value type for `WindowGroup(for: RepositoryReference.self)`.
/// The ``displayName`` is derived from the last path component so the struct
/// contains no redundant mutable state.
struct RepositoryReference: Codable, Hashable, Sendable {
    /// Absolute filesystem path to the repository's working directory.
    let path: String

    /// Human-readable name derived from the last path component.
    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
