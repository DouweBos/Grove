// Refs/GitSidebarRow.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// A sidebar row: tinted symbol, title, optional mono detail and a trailing accessory. Colours give way on the selection.
public struct GitSidebarRow<Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.backgroundProminence) private var prominence
    private let title: String
    private let symbol: String
    private let tint: Color?
    private let detail: String?
    private let detailSymbol: String?
    private let detailTint: Color?
    private let isEmphasized: Bool
    private let isDimmed: Bool
    private let badgeSymbol: String?
    private let accessory: () -> Accessory

    /// - Parameters:
    ///   - tint: The symbol's colour; nil is the secondary text colour.
    ///   - detailSymbol: Leads the detail, e.g. the merge symbol on a merged pull request's number.
    ///   - isDimmed: Recedes the title, for refs that are done with, like a merged branch.
    ///   - badgeSymbol: Small symbol on the icon's corner, e.g. a branch also checked out in a worktree.
    public init(title: String, symbol: String, tint: Color? = nil, detail: String? = nil, detailSymbol: String? = nil,
                detailTint: Color? = nil, isEmphasized: Bool = false, isDimmed: Bool = false, badgeSymbol: String? = nil,
                @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.detail = detail
        self.detailSymbol = detailSymbol
        self.detailTint = detailTint
        self.isEmphasized = isEmphasized
        self.isDimmed = isDimmed
        self.badgeSymbol = badgeSymbol
        self.accessory = accessory
    }

    /// Fixed colours are unreadable on the accent selection; hierarchical styles adapt.
    private var isOnSelection: Bool { prominence == .increased }

    private func shape(_ color: Color, else fallback: HierarchicalShapeStyle = .primary) -> AnyShapeStyle {
        isOnSelection ? AnyShapeStyle(fallback) : AnyShapeStyle(color)
    }

    public var body: some View {
        HStack(spacing: 6 * style.fontScale) {
            Image(systemName: symbol)
                .font(style.font(12))
                .foregroundStyle(shape(tint ?? style.textSecondary))
                .frame(width: 16 * style.fontScale)
                .overlay(alignment: .bottomTrailing) {
                    if let badgeSymbol {
                        Image(systemName: badgeSymbol)
                            .font(style.font(8, .bold))
                            .foregroundStyle(shape(style.info))
                            // A ring in the row background separates the badge from the icon beneath it.
                            .background(Circle().fill(style.background).padding(-1.5))
                            .offset(x: 3, y: 3)
                    }
                }
            Text(title)
                .font(style.font(13, isEmphasized ? .semibold : .regular))
                .foregroundStyle(shape(style.textPrimary))
                .opacity(isDimmed ? 0.55 : 1)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail {
                HStack(spacing: 2) {
                    if let detailSymbol {
                        Image(systemName: detailSymbol)
                            .font(style.font(9, .semibold))
                            .foregroundStyle(shape(detailTint ?? style.textSecondary, else: .secondary))
                    }
                    Text(detail)
                        .font(style.font(11, .regular, .monospaced))
                        .foregroundStyle(shape(style.textSecondary, else: .secondary))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            accessory()
                .foregroundStyle(shape(style.textSecondary, else: .secondary))
        }
    }
}

extension GitSidebarRow where Accessory == EmptyView {
    public init(title: String, symbol: String, tint: Color? = nil, detail: String? = nil, detailSymbol: String? = nil,
                detailTint: Color? = nil, isEmphasized: Bool = false, isDimmed: Bool = false, badgeSymbol: String? = nil) {
        self.init(title: title, symbol: symbol, tint: tint, detail: detail, detailSymbol: detailSymbol, detailTint: detailTint,
                  isEmphasized: isEmphasized, isDimmed: isDimmed, badgeSymbol: badgeSymbol) { EmptyView() }
    }
}

/// Compact "↑2 ↓1" counts, hidden when level.
public struct GitAheadBehind: View {
    @Environment(\.gitStyle) private var style
    private let ahead: Int
    private let behind: Int

    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }

    public var body: some View {
        if ahead > 0 || behind > 0 {
            HStack(spacing: 4) {
                if ahead > 0 { Text("↑\(ahead)") }
                if behind > 0 { Text("↓\(behind)") }
            }
            .font(style.font(11, .medium, .monospaced))
            .help("\(ahead) ahead, \(behind) behind")
        }
    }
}

/// A branch's CI verdict: the status symbol, small, in its colour unless the row is selected.
struct BranchCIIcon: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.backgroundProminence) private var prominence
    let status: BranchCIStatus

    var body: some View {
        Image(systemName: Self.symbol(status.status))
            .font(style.font(10, .semibold))
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
            .accessibilityLabel(status.tooltip)
    }

    private var color: Color {
        switch status.status {
        case .queued, .inProgress: style.warning
        case .success: style.success
        case .failure: style.danger
        case .cancelled, .skipped, .neutral: style.textSecondary
        }
    }

    static func symbol(_ status: CIRunStatus) -> String {
        switch status {
        case .queued: "clock.fill"
        case .inProgress: "arrow.triangle.2.circlepath.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .cancelled: "slash.circle.fill"
        case .skipped: "arrow.uturn.right.circle"
        case .neutral: "minus.circle"
        }
    }
}
#endif
