// Components/AvatarView.swift
// Grove
//
// Circular author avatar: Gravatar when available, initials on a tinted fill otherwise.

import CryptoKit
import SwiftUI

enum AvatarSize {
    case small
    case medium
    case large

    var points: CGFloat {
        switch self {
        case .small: 20
        case .medium: 28
        case .large: 40
        }
    }

    var font: Font {
        switch self {
        case .small: .system(size: 8, weight: .semibold, design: .rounded)
        case .medium: .system(size: 11, weight: .semibold, design: .rounded)
        case .large: .system(size: 15, weight: .semibold, design: .rounded)
        }
    }
}

struct AvatarView: View {
    let name: String
    let email: String
    var size: AvatarSize = .medium
    /// Fill for the initials fallback; defaults to a lane color derived from the email.
    var tint: Color?

    var body: some View {
        AsyncImage(url: gravatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                initials
            }
        }
        .frame(width: size.points, height: size.points)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 0.5))
        .accessibilityLabel(name)
    }

    private var initials: some View {
        let color = tint ?? Theme.laneColor(Self.stableHash(email.lowercased()))
        return Text(Self.initials(for: name))
            .font(size.font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.18))
    }

    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)".uppercased()
    }

    /// djb2, because `hashValue` is randomized per process and colors must stay put.
    static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Int(hash % 1024)
    }

    // `d=404` makes Gravatar fail for unknown addresses so the initials show instead of a stock image.
    private var gravatarURL: URL? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8)).map { String(format: "%02hhx", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(Int(size.points * 2))&d=404")
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.md) {
        AvatarView(name: "Jane Developer", email: "jane@example.com", size: .small)
        AvatarView(name: "Bob Contributor", email: "bob@example.com")
        AvatarView(name: "Alice Reviewer", email: "alice@example.com", size: .large)
        AvatarView(name: "Single", email: "single@example.com", size: .large, tint: Theme.accent)
    }
    .padding()
    .background(Theme.surface)
}
