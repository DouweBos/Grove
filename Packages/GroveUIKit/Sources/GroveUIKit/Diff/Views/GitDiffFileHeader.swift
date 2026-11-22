// Diff/Views/GitDiffFileHeader.swift
// GroveUIKit
//
// The row over a file's diff: what changed, its name and folder, and the diff's controls.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitDiffFileHeader<Leading: View, Trailing: View>: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var host
    private let path: String?
    private let title: String?
    private let status: FileStatus?
    private let leading: () -> Leading
    private let trailing: () -> Trailing
    @State private var width: CGFloat = .infinity

    /// - Parameters:
    ///   - title: Shown instead of the path's name and folder.
    ///   - leading: Before the name, e.g. the app's file icon.
    public init(path: String?, title: String? = nil, status: FileStatus? = nil,
                @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.path = path
        self.title = title
        self.status = status
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if let status { GitStatusIcon(status: status) }
            leading()
            name
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 44 * style.fontScale)
        .clipped()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }
    }

    @ViewBuilder
    private var name: some View {
        if let title {
            primary(title).truncationMode(.head)
        } else if let path {
            let split = Self.split(path)
            HStack(spacing: GitMetrics.Spacing.sm) {
                primary(split.name).layoutPriority(1)
                // Narrower, the folder would be a letter's sliver beside the name.
                if !split.directory.isEmpty, width >= 420 * style.fontScale {
                    Text(split.directory)
                        .font(style.monoCaption)
                        .foregroundStyle(style.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
            }
            .layoutPriority(-1)
            .help(path)
            .contextMenu {
                Button("Copy Path") {
                    host.copy(path)
                    host.toast("Copied Path")
                }
            }
        }
    }

    private func primary(_ text: String) -> some View {
        Text(text)
            .font(style.font(13, .semibold))
            .foregroundStyle(style.textPrimary)
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private static func split(_ path: String) -> (name: String, directory: String) {
        let name = (path as NSString).lastPathComponent
        return (name, String(path.dropLast(name.count)))
    }
}

extension GitDiffFileHeader where Leading == EmptyView, Trailing == EmptyView {
    public init(path: String?, title: String? = nil, status: FileStatus? = nil) {
        self.init(path: path, title: title, status: status, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

#Preview {
    GitDiffFileHeader(path: "Sources/Grove/Views/HistoryView.swift", status: .modified)
        .frame(width: 520)
        .gitPanel()
}
#endif
