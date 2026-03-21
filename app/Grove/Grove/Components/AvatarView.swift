// Components/AvatarView.swift
// Grove
//
// Circular avatar displaying a Gravatar image or a deterministic initials
// fallback for commit authors, blame annotations, and pull-request actors.

import SwiftUI
import CryptoKit

// MARK: - AvatarSize

/// The three canonical sizes used throughout the UI.
enum AvatarSize {
    case small
    case medium
    case large

    /// Point dimension for the circle.
    var points: CGFloat {
        switch self {
        case .small:  return 20
        case .medium: return 28
        case .large:  return 36
        }
    }

    /// Font used for the initials label.
    var font: Font {
        switch self {
        case .small:  return .system(size: 8,  weight: .semibold)
        case .medium: return .system(size: 11, weight: .semibold)
        case .large:  return .system(size: 14, weight: .semibold)
        }
    }
}

// MARK: - AvatarView

/// A circular avatar that loads a Gravatar image and falls back to a
/// coloured initials circle when the network is unavailable or the
/// address has no Gravatar.
///
/// Usage:
/// ```swift
/// AvatarView(name: commit.authorName, email: commit.authorEmail)
/// AvatarView(name: commit.authorName, email: commit.authorEmail, size: .small)
/// ```
struct AvatarView: View {

    // MARK: Properties

    let name: String
    let email: String
    var size: AvatarSize = .medium

    // MARK: Body

    var body: some View {
        AsyncImage(url: gravatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            default:
                initialsView
            }
        }
        .frame(width: size.points, height: size.points)
        .clipShape(Circle())
    }

    // MARK: Private — Initials Fallback

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(avatarColor.gradient)
            Text(initials)
                .font(size.font)
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last  = parts.dropFirst().first?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .teal, .indigo]
        let index = abs(email.hashValue) % palette.count
        return palette[index]
    }

    // MARK: Private — Gravatar

    /// Returns the Gravatar URL for the given email using MD5 hashing.
    ///
    /// The `d=404` parameter instructs Gravatar to return HTTP 404 instead of
    /// a generated image so that ``AsyncImage`` falls back to the placeholder.
    private var gravatarURL: URL? {
        let normalised = email.trimmingCharacters(in: .whitespaces).lowercased()
        let hash = Insecure.MD5
            .hash(data: Data(normalised.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
        let dimension = Int(size.points * 2) // 2× for Retina
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(dimension)&d=404")
    }
}

// MARK: - Preview

#Preview("Avatar Sizes") {
    HStack(spacing: 16) {
        VStack(spacing: 8) {
            AvatarView(name: "Jane Developer", email: "jane@example.com", size: .small)
            Text("small").font(.caption2)
        }
        VStack(spacing: 8) {
            AvatarView(name: "Jane Developer", email: "jane@example.com", size: .medium)
            Text("medium").font(.caption2)
        }
        VStack(spacing: 8) {
            AvatarView(name: "Jane Developer", email: "jane@example.com", size: .large)
            Text("large").font(.caption2)
        }
    }
    .padding()
}

#Preview("Avatar Initials Palette") {
    let authors: [(String, String)] = [
        ("Jane Developer", "jane@example.com"),
        ("Bob Contributor", "bob@example.com"),
        ("Alice Reviewer", "alice@example.com"),
        ("Carlos Ruiz", "carlos@example.com"),
        ("Single", "single@example.com"),
    ]
    HStack(spacing: 12) {
        ForEach(authors, id: \.1) { name, email in
            AvatarView(name: name, email: email, size: .large)
        }
    }
    .padding()
}
