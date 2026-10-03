// Models/SignatureStatus.swift
// GroveKit

import Foundation

/// The verification state of a GPG or SSH commit signature.
///
/// Maps to git's `%G?` format placeholder values:
/// - `G` → `.verified`
/// - `B`, `E`, `X`, `Y`, `R` → `.unverified`
/// - `N` → `.unsigned`
public enum SignatureStatus: Hashable, Sendable {
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
