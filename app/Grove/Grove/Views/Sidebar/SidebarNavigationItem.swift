// Views/Sidebar/SidebarNavigationItem.swift
// Grove

import SwiftUI

/// A single navigation row in the top section of the sidebar.
///
/// Renders an SF Symbol icon, a label, and an optional badge (e.g. Working Copy count).
struct SidebarNavigationItem: View {

    let item: SidebarItem
    let icon: String
    let label: String
    var badge: Int = 0

    var body: some View {
        Label {
            HStack {
                Text(label)
                Spacer()
                SidebarBadge(count: badge)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .tag(item)
    }
}

#Preview {
    List {
        SidebarNavigationItem(item: .workingCopy, icon: "tray", label: "Working Copy", badge: 16)
        SidebarNavigationItem(item: .history, icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "History")
        SidebarNavigationItem(item: .stashes, icon: "tray.2", label: "Stashes")
        SidebarNavigationItem(item: .reflog, icon: "clock.arrow.circlepath", label: "Reflog")
        SidebarNavigationItem(item: .blame, icon: "text.line.first.and.arrowtriangle.forward", label: "Blame")
        SidebarNavigationItem(item: .pullRequests, icon: "arrow.triangle.pull", label: "Pull Requests")
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 240)
}
