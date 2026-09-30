// Views/CI/CIStatusStyle.swift
// Grove
//
// How a run, job or step status looks everywhere it shows.

import SwiftUI

extension CIRunStatus {
    var symbol: String {
        switch self {
        case .queued: "clock.fill"
        case .inProgress: "arrow.triangle.2.circlepath.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .cancelled: "slash.circle.fill"
        case .skipped: "arrow.uturn.right.circle"
        case .neutral: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .queued, .inProgress: Theme.warning
        case .success: Theme.success
        case .failure: Theme.danger
        case .cancelled, .skipped, .neutral: Theme.textSecondary
        }
    }

    var badgeTone: StatusBadge.Tone {
        switch self {
        case .queued, .inProgress: .caution
        case .success: .positive
        case .failure: .negative
        case .cancelled, .skipped, .neutral: .neutral
        }
    }
}

/// The status symbol in its color; pulses while the run is going.
struct CIStatusIcon: View {
    let status: CIRunStatus
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, isActive: status == .inProgress)
            .accessibilityLabel(status.title)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        ForEach(CIRunStatus.allCases, id: \.self) { status in
            HStack {
                CIStatusIcon(status: status)
                Text(status.title).font(.rowTitle)
                Spacer()
                StatusBadge(title: status.title, symbol: status.symbol, tone: status.badgeTone)
            }
        }
    }
    .frame(width: 260)
    .padding()
    .background(Theme.surface)
}
