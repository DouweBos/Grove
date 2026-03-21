// Views/Repositories/RepositoryGroupRow.swift
// Grove
//
// A row representing a bookmark group in the sidebar.
// Uses an orange folder icon.

import SwiftUI

// MARK: - RepositoryGroupRow

/// Compact sidebar row for a bookmark group — orange folder icon + group name.
///
/// The disclosure triangle for expand / collapse is rendered by the enclosing
/// `DisclosureGroup` in ``RepositoryGroupSection``; this view is responsible
/// only for the icon and label.
struct RepositoryGroupRow: View {

    let group: BookmarkGroupData

    var body: some View {
        Label {
            Text(group.name)
                .fontWeight(.medium)
                .lineLimit(1)
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        RepositoryGroupRow(group: BookmarkGroupData(
            id: UUID(),
            name: "Work",
            sortOrder: 0,
            isExpanded: true
        ))
        RepositoryGroupRow(group: BookmarkGroupData(
            id: UUID(),
            name: "Personal",
            sortOrder: 1,
            isExpanded: true
        ))
    }
    .frame(width: 220, height: 120)
}
