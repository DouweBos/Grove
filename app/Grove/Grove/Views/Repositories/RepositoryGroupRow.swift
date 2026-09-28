// Views/Repositories/RepositoryGroupRow.swift
// Grove

import SwiftUI

/// Group label in the browser sidebar: accent folder, name, repository count.
struct RepositoryGroupRow: View {

    let group: BookmarkGroupData
    var count: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(group.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.subtleFill, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        RepositoryGroupRow(group: BookmarkGroupData(id: UUID(), name: "Work", sortOrder: 0, isExpanded: true), count: 12)
        RepositoryGroupRow(group: BookmarkGroupData(id: UUID(), name: "Personal", sortOrder: 1, isExpanded: true), count: 3)
    }
    .listStyle(.sidebar)
    .frame(width: 240, height: 120)
}
