// Domain/CI/CIPollSchedule.swift
// Grove
//
// How often the Actions tab asks the host for changes.

import Foundation

nonisolated enum CIPollSchedule {
    static let idle: TimeInterval = 60
    static let maximum: TimeInterval = 300

    /// Seconds until the next poll: 5s, then 10s, then 30s while runs are active, a minute when idle,
    /// and doubling from a minute up to five after failures (errors, 403, 429).
    static func interval(activeFor: TimeInterval?, consecutiveFailures: Int = 0) -> TimeInterval {
        if consecutiveFailures > 0 {
            return min(maximum, idle * pow(2, Double(min(consecutiveFailures, 8) - 1)))
        }
        guard let activeFor else { return idle }
        if activeFor < 30 { return 5 }
        if activeFor < 120 { return 10 }
        return 30
    }
}
