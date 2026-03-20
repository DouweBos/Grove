// Views/History/CommitDetailHeader.swift
// Grove

import SwiftUI

/// Header in the commit detail panel showing avatar, author, date, SHA, and verified badge.
struct CommitDetailHeader: View {

    let commit: CommitInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row with avatar
            HStack(alignment: .top, spacing: 10) {
                AuthorAvatarView(name: commit.authorName, email: commit.authorEmail)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(commit.authorName)
                            .fontWeight(.semibold)
                        if commit.isSigned {
                            Label("Verified", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                        }
                    }
                    Text(commit.authorEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(commit.authorDate.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Commit SHA
            HStack(spacing: 4) {
                Text("SHA:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(commit.id)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Commit message
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.summary)
                    .fontWeight(.medium)
                    .textSelection(.enabled)

                if let body = commit.body, !body.isEmpty {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - AuthorAvatarView

/// Circular avatar generated from author initials and a deterministic color.
private struct AuthorAvatarView: View {

    let name: String
    let email: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.dropFirst().first?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .teal, .indigo]
        let index = abs(email.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor.gradient)
            Text(initials)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

#Preview {
    CommitDetailHeader(commit: MockData.commits[0])
        .padding()
        .frame(width: 400)
}
