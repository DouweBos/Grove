// Views/PullRequests/PullRequestRow.swift
// Grove

import SwiftUI

/// A single row in the pull request list.
///
/// Shows: PR number, title, author, relative date, source → target branches,
/// draft badge, label pills, and checks-status icon.
struct PullRequestRow: View {

    let pr: PullRequestInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top row: number, title, checks icon
            HStack(alignment: .top, spacing: 6) {
                Text("#\(pr.id)")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)

                Text(pr.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                checksIcon
            }

            // Branch flow: source → target
            HStack(spacing: 4) {
                Label(pr.sourceBranch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(pr.targetBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Bottom row: author, date, draft badge, labels
            HStack(spacing: 6) {
                PRAuthorAvatarView(name: pr.authorName)
                    .frame(width: 16, height: 16)

                Text(pr.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(pr.updatedDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                if pr.isDraft {
                    draftBadge
                }

                ForEach(pr.labels.prefix(2)) { label in
                    PRLabelPill(label: label)
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Checks Icon

    @ViewBuilder
    private var checksIcon: some View {
        switch pr.checksStatus {
        case .passing:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
        case .failing:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
        case .pending:
            Image(systemName: "clock.circle.fill")
                .foregroundStyle(.yellow)
                .imageScale(.small)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Draft Badge

    private var draftBadge: some View {
        Text("Draft")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

// MARK: - PRLabelPill

/// A small coloured pill for a pull request label.
struct PRLabelPill: View {

    let label: PRLabel

    var body: some View {
        Text(label.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(labelColor.isDark ? .white : .black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(labelColor, in: Capsule())
    }

    private var labelColor: Color {
        Color(hex: label.color) ?? .accentColor
    }
}

// MARK: - PRAuthorAvatarView

/// Tiny circular avatar generated from the author's initials.
struct PRAuthorAvatarView: View {

    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last  = parts.dropFirst().first?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .teal, .indigo]
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let index = Int(hash % UInt64(colors.count))
        return colors[index]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor.gradient)
            Text(initials)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Color Helpers

private extension Color {
    /// Initialise from a hex string such as `"0075ca"` or `"#0075ca"`.
    init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >>  8) & 0xFF) / 255.0
        let b = Double( value        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Returns `true` when the colour is perceptually dark.
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
    }
}

#Preview {
    List {
        ForEach(MockData.pullRequests) { pr in
            PullRequestRow(pr: pr)
        }
    }
    .listStyle(.plain)
    .frame(width: 320, height: 320)
}
