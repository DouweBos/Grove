// Diff/Views/GitDiffPane.swift
// GroveUIKit
//
// A file's diff under its header: counts, side, the app's extras, and how it's shown.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitDiffPane<Leading: View, Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    private let diff: DiffResult?
    private let path: String?
    private let title: String?
    private let status: FileStatus?
    private let isLoading: Bool
    private let options: GitDiffOptions
    private let staging: GitDiffStaging?
    private let sideSwitch: GitDiffSideSwitch?
    private let ignoresWhitespace: Binding<Bool>?
    private let annotations: GitDiffAnnotations?
    private let images: GitDiffImages?
    private let leading: () -> Leading
    private let accessory: () -> Accessory
    @State private var width: CGFloat = .infinity

    /// - Parameters:
    ///   - title: Shown instead of the path's name and folder.
    ///   - staging: What its hunks can do; nil shows no buttons.
    ///   - sideSwitch: Which side of the working copy it shows.
    ///   - ignoresWhitespace: Nil where the diff can't hide whitespace changes.
    ///   - annotations: The app's rows under lines, e.g. review comments.
    ///   - images: Where image files are read from; without it they show as binary.
    ///   - leading: Before the file's name, e.g. the app's file icon.
    ///   - accessory: The app's own controls, e.g. a viewed mark.
    public init(diff: DiffResult?, path: String? = nil, title: String? = nil, status: FileStatus? = nil,
                isLoading: Bool = false, options: GitDiffOptions = GitDiffOptions(), staging: GitDiffStaging? = nil,
                sideSwitch: GitDiffSideSwitch? = nil, ignoresWhitespace: Binding<Bool>? = nil,
                annotations: GitDiffAnnotations? = nil, images: GitDiffImages? = nil,
                @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.diff = diff
        self.path = path
        self.title = title
        self.status = status
        self.isLoading = isLoading
        self.options = options
        self.staging = staging
        self.sideSwitch = sideSwitch
        self.ignoresWhitespace = ignoresWhitespace
        self.annotations = annotations
        self.images = images
        self.leading = leading
        self.accessory = accessory
    }

    private var shownPath: String? { path ?? diff?.filePath }

    private var showsImage: Bool {
        guard images != nil, let shownPath else { return false }
        return GitImageDiffView.supports(path: shownPath)
    }

    public var body: some View {
        VStack(spacing: 0) {
            GitDiffFileHeader(path: shownPath, title: title, status: status, leading: leading) { controls }
                // A width check, not ViewThatFits: measuring every variant makes opening a panel slow.
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The counts and the side's badge give way before the controls do.
    private var isCompact: Bool { width < 520 * style.fontScale }

    private var controls: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if !isCompact, !showsImage, let stats = diff?.stats, stats.additions + stats.deletions > 0 {
                DiffCounts(stats: stats)
            }
            if let sideSwitch { side(sideSwitch) }
            accessory()
            if !showsImage {
                if let ignoresWhitespace { IgnoreWhitespaceToggle(isOn: ignoresWhitespace) }
                GitWrapLinesToggle(isOn: options.wrapsLines)
                GitDiffLayoutPicker(layout: options.layout)
            }
        }
    }

    @ViewBuilder
    private func side(_ value: GitDiffSideSwitch) -> some View {
        if let select = value.select {
            Picker("Side", selection: Binding(get: { value.side }, set: { if $0 != value.side { select($0) } })) {
                Text("Unstaged").tag(DiffSide.unstaged)
                Text("Staged").tag(DiffSide.staged)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .gitClickable()
        } else if !isCompact {
            let staged = value.side == .staged
            GitStatusBadge(title: staged ? "Staged" : "Unstaged", symbol: staged ? "checkmark.circle" : "pencil", tone: .neutral)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        if showsImage, let images, let shownPath {
            GitImageDiffView(images, path: shownPath, oldPath: diff?.oldPath, mode: options.imageMode)
        } else if let diff {
            GitDiffView(diff: diff, options: options, staging: staging, annotations: annotations)
        } else if isLoading {
            ProgressView().controlSize(.small)
        } else if shownPath == nil {
            GitEmptyState(systemImage: "doc.text.magnifyingglass", title: "No File Selected")
        } else {
            GitEmptyState(systemImage: "doc.questionmark", title: "No Diff Available",
                          subtitle: "There's no text diff to show for this file.")
        }
    }
}

extension GitDiffPane where Leading == EmptyView, Accessory == EmptyView {
    public init(diff: DiffResult?, path: String? = nil, title: String? = nil, status: FileStatus? = nil,
                isLoading: Bool = false, options: GitDiffOptions = GitDiffOptions(), staging: GitDiffStaging? = nil,
                sideSwitch: GitDiffSideSwitch? = nil, ignoresWhitespace: Binding<Bool>? = nil,
                annotations: GitDiffAnnotations? = nil, images: GitDiffImages? = nil) {
        self.init(diff: diff, path: path, title: title, status: status, isLoading: isLoading, options: options,
                  staging: staging, sideSwitch: sideSwitch, ignoresWhitespace: ignoresWhitespace,
                  annotations: annotations, images: images, leading: { EmptyView() }, accessory: { EmptyView() })
    }
}

#Preview {
    GitDiffPane(diff: MockData.diffResult(for: "WorkingCopyViewModel.swift"), status: .modified,
                staging: GitDiffStaging(side: .unstaged) { _, _, _ in }, sideSwitch: GitDiffSideSwitch(side: .unstaged))
        .frame(width: 700, height: 480)
        .gitPanel()
}
#endif
