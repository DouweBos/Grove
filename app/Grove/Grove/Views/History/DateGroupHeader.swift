// Views/History/DateGroupHeader.swift
// Grove

import SwiftUI

/// Day label between commit groups; keeps the graph lanes running through it.
struct DateGroupHeader: View {
    let date: Date
    var lanes: [GraphLine] = []
    var maxGraphColumns = 1
    var showsGraph = true

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if showsGraph {
                CommitGraphPassThrough(lanes: lanes, maxColumns: maxGraphColumns)
            }
            SectionLabel(title: date.commitDayTitle)
        }
        .padding(.leading, Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.md)
        .frame(height: 28)
    }
}

#Preview {
    VStack(spacing: 0) {
        DateGroupHeader(date: .now, showsGraph: false)
        DateGroupHeader(date: .now.addingTimeInterval(-86_400),
                        lanes: [GraphLine(kind: .passThrough, fromColumn: 0, toColumn: 0, colorIndex: 0)])
    }
    .frame(width: 300)
    .panel()
    .padding()
    .background(Theme.background)
}
