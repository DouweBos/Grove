// Components/VerifiedBadge.swift
// Grove
//
// Pill badge indicating GPG/SSH commit signature verification status.
// Shown in commit detail headers and history list rows.

import SwiftUI

// MARK: - SignatureStatus

/// The verification state of a GPG or SSH commit signature.
///
/// Maps to git's `%G?` format placeholder values:
/// - `G` → `.verified`
/// - `B`, `E`, `X`, `Y`, `R` → `.unverified`
/// - `N` → `.unsigned`
enum SignatureStatus: Hashable, Sendable {
    /// Signature is present and the key is trusted.
    case verified
    /// Signature is present but the key is not trusted or the signature is invalid.
    case unverified
    /// No signature on this commit.
    case unsigned

    /// Construct from the single-character `%G?` output of `git log`.
    init(gitCode: Character) {
        switch gitCode {
        case "G":              self = .verified
        case "N", " ", "\0":  self = .unsigned
        default:               self = .unverified
        }
    }
}

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
