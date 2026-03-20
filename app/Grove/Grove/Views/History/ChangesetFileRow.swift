// Views/History/ChangesetFileRow.swift
// Grove

import SwiftUI

/// A file row in the commit changeset list.
///
/// Shows status icon, file name, and a proportional additions/deletions change bar.
struct ChangesetFileRow: View {

    let fileDiff: FileDiff
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 14)

            Text(fileDiff.path.lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            ChangeBar(additions: fileDiff.stats.additions, deletions: fileDiff.stats.deletions)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch fileDiff.status {
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
        case .renamed:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
        case .copied:
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(.blue)
        default:
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ChangeBar

/// Visual additions/deletions bar (green + red proportional segments).
struct ChangeBar: View {

    let additions: Int
    let deletions: Int

    private var total: Int { max(additions + deletions, 1) }
    private var maxSegments: Int { 5 }

    private var additionSegments: Int {
        Int(round(Double(additions) / Double(total) * Double(maxSegments)))
    }

    private var deletionSegments: Int {
        maxSegments - additionSegments
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<additionSegments, id: \.self) { _ in
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 6, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
            ForEach(0..<deletionSegments, id: \.self) { _ in
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 6, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
    }
}

private extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}

#Preview {
    List {
        ForEach(MockData.commitFileDiffs, id: \.path) { diff in
            ChangesetFileRow(fileDiff: diff)
        }
    }
    .listStyle(.plain)
    .frame(width: 300, height: 200)
}
