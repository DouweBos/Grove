// Views/History/DateGroupHeader.swift
// Grove

import SwiftUI

/// A date-group header row displayed between commit groups in the history list.
///
/// Renders "Today", "Yesterday", or a formatted date.
struct DateGroupHeader: View {

    let date: Date

    var body: some View {
        HStack {
            Text(formattedTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(nil)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var formattedTitle: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
    }
}

#Preview {
    List {
        DateGroupHeader(date: Date())
        Text("Commit 1")
        DateGroupHeader(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        Text("Commit 2")
    }
    .listStyle(.sidebar)
    .frame(width: 300, height: 200)
}
