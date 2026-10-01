// Views/CI/CIRunRow.swift
// Grove

import SwiftUI

/// One workflow run in the list: status, title, then workflow, branch and age.
struct CIRunRow: View {
    let run: CIRun
    /// A notification is due when it finishes.
    var isWatched = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            CIStatusIcon(status: run.status)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(verbatim: "\(run.workflowName) #\(run.number)").lineLimit(1)
                    if let branch = run.branch {
                        Text(branch).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if isWatched {
                        Image(systemName: "bell.fill").help("Notifies when finished")
                    }
                    Text(run.createdDate, format: .relative(presentation: .named)).lineLimit(1).fixedSize()
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(MockData.ciRuns) { CIRunRow(run: $0).selectableRow(isSelected: $0.id == 146) }
    }
    .padding(Theme.Spacing.sm)
    .frame(width: 360)
    .panel()
    .padding()
    .background(Theme.background)
}
