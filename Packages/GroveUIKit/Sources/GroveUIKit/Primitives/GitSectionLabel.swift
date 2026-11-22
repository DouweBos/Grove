// Primitives/GitSectionLabel.swift
// GroveUIKit
//
// Muted label above a group of rows, e.g. "Branches" or "Staged".

#if os(macOS)
import SwiftUI

public struct GitSectionLabel<Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    private let title: String
    private let count: Int?
    private let accessory: () -> Accessory

    public init(title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.count = count
        self.accessory = accessory
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            Text(title)
                .font(style.sectionLabel)
                .foregroundStyle(style.textSecondary)
            if let count {
                Text("\(count)")
                    .font(style.font(11, .semibold, .rounded))
                    .foregroundStyle(style.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(style.subtleFill, in: Capsule())
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

extension GitSectionLabel where Accessory == EmptyView {
    public init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

#Preview {
    GitSectionLabel(title: "Staged", count: 3).padding().frame(width: 300)
}
#endif
