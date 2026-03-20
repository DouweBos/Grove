// Views/Stashes/StashRow.swift
// Grove

import SwiftUI

/// A single row in the stash list.
///
/// Shows the stash index, message, branch context, SHA, and date.
struct StashRow: View {

    let stash: StashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Message line
            Text(stash.message)
                .font(.subheadline)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                // Branch chip
                if let branch = stash.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // SHA
                Text(String(stash.sha.prefix(7)))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)

                // Date
                Text(stash.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        ForEach(MockData.stashEntries) { stash in
            StashRow(stash: stash)
        }
    }
    .listStyle(.plain)
    .frame(width: 300, height: 200)
}
