// History/Parts/CommitAvatar.swift
// GroveUIKit
//
// An author's picture when the app offers one, initials on a tinted circle otherwise.

#if os(macOS)
import AppKit
import SwiftUI

enum CommitAvatarSize {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: 20
        case .medium: 28
        case .large: 40
        }
    }
}

struct CommitAvatar: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.historyHost) private var host
    let name: String
    let email: String
    var size: CommitAvatarSize = .medium
    /// Fill for the initials; defaults to a lane colour taken from the email.
    var tint: Color?

    var body: some View {
        let side = size.points * style.fontScale
        Group {
            if let url = host.avatarURL?(email, Int(side * 2)) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { initials(side) }
                }
            } else {
                initials(side)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(style.border, lineWidth: 0.5))
        .accessibilityLabel(name)
    }

    private func initials(_ side: CGFloat) -> some View {
        let color = tint ?? style.lane(AvatarInitials.colorIndex(email))
        return Text(AvatarInitials.of(name))
            .font(.system(size: side * 0.39, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.18))
    }
}

enum AvatarInitials {
    static func of(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)".uppercased()
    }

    /// djb2 of the lowercased email, because `hashValue` is randomized per process and colours must stay put.
    static func colorIndex(_ email: String) -> Int {
        var hash: UInt64 = 5381
        for byte in email.lowercased().utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Int(hash % 1024)
    }
}

/// Pictures for the commit table, which draws its rows itself: each email is fetched once per table.
@MainActor
final class AvatarImages {
    private var images: [String: NSImage] = [:]
    private var requested: Set<String> = []
    var onLoad: ((String) -> Void)?

    func image(email: String, url: URL?) -> NSImage? {
        if let image = images[email] { return image }
        guard let url, !requested.contains(email) else { return nil }
        requested.insert(email)
        Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return }
            self?.images[email] = image
            self?.onLoad?(email)
        }
        return nil
    }
}
#endif
