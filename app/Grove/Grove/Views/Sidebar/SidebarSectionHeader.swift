// Views/Sidebar/SidebarSectionHeader.swift
// Grove

import SwiftUI

/// Uppercase, muted gray section label used in the sidebar (BRANCHES, REMOTES, TAGS).
struct SidebarSectionHeader: View {

    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

#Preview {
    List {
        Section(header: SidebarSectionHeader(title: "Branches")) {
            Text("main")
        }
    }
    .listStyle(.sidebar)
    .frame(width: 200, height: 100)
}
