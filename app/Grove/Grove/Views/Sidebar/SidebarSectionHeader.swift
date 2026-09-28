// Views/Sidebar/SidebarSectionHeader.swift
// Grove

import SwiftUI

/// Muted section label used in the sidebar (Branches, Remotes, Tags).
struct SidebarSectionHeader: View {

    let title: String

    var body: some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Theme.textSecondary)
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
