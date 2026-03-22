// Models/CloneTypes.swift
// Grove
//
// Clone operation progress types.

import Foundation

// MARK: - CloneProgress

/// Progress report emitted during a `git clone` operation.
struct CloneProgress: Sendable {
    let phase: ClonePhase
    let receivedObjects: Int
    let totalObjects: Int
    let receivedBytes: Int64
    /// Progress fraction in [0, 1].
    var fractionCompleted: Double {
        guard totalObjects > 0 else { return 0 }
        return Double(receivedObjects) / Double(totalObjects)
    }
}

// MARK: - ClonePhase

/// Phases of a clone operation.
enum ClonePhase: Sendable {
    case fetching
    case indexing
    case checkingOut
}
