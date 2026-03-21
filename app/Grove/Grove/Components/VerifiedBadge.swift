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
            badge(
                icon: "checkmark.seal.fill",
                label: "Verified",
                foreground: .white,
                background: Color(red: 0x2E / 255, green: 0xA0 / 255, blue: 0x43 / 255)
            )
        case .unverified:
            badge(
                icon: "exclamationmark.triangle.fill",
                label: "Unverified",
                foreground: Color(white: 0.3),
                background: Color(white: 0.78)
            )
        }
    }

    // MARK: Private

    private func badge(
        icon: String,
        label: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
    }
}

// MARK: - Preview

#Preview("Verified Badge States") {
    HStack(spacing: 12) {
        VStack(spacing: 6) {
            VerifiedBadge(status: .verified)
            Text(".verified").font(.caption2).foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            VerifiedBadge(status: .unverified)
            Text(".unverified").font(.caption2).foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            // .unsigned renders EmptyView — show a placeholder label instead
            Text("(no badge)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(".unsigned").font(.caption2).foregroundStyle(.secondary)
        }
    }
    .padding()
}
