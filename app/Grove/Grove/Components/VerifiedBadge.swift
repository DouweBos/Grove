// Components/VerifiedBadge.swift
// Grove
//
// Pill badge indicating GPG/SSH commit signature verification status.
// Shown in commit detail headers and history list rows.

import GroveKit
import SwiftUI

// MARK: - VerifiedBadge

/// A compact pill badge showing the GPG/SSH signature state of a commit.
///
/// Renders nothing when ``SignatureStatus`` is `.unsigned`.
///
/// Usage:
/// ```swift
/// VerifiedBadge(status: commit.isSigned ? .verified : .unsigned)
/// ```
struct VerifiedBadge: View {

    // MARK: Properties

    let status: SignatureStatus

    // MARK: Body

    var body: some View {
        switch status {
        case .unsigned:
            EmptyView()
        case .verified:
            StatusBadge(title: "Verified", symbol: "checkmark.seal.fill", tone: .positive)
        case .unverified:
            StatusBadge(title: "Unverified", symbol: "exclamationmark.triangle.fill", tone: .caution)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        VerifiedBadge(status: .verified)
        VerifiedBadge(status: .unverified)
    }
    .padding()
    .background(Theme.surface)
}
