// Views/Sidebar/SidebarBadge.swift
// Grove

import SwiftUI

/// Numeric badge displayed on sidebar navigation items (e.g. Working Copy change count).
struct SidebarBadge: View {

    let count: Int

    var body: some View {
        if count > 0 { // swiftlint:disable:this empty_count
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.5), in: Capsule())
                .monospacedDigit()
        }
    }
}

#Preview {
    HStack {
        SidebarBadge(count: 0)
        SidebarBadge(count: 5)
        SidebarBadge(count: 16)
        SidebarBadge(count: 123)
    }
    .padding()
}
