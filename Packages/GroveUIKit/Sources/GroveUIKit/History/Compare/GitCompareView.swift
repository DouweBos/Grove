// History/Compare/GitCompareView.swift
// GroveUIKit
//
// Two refs side by side: what each has that the other lacks, whether merging would conflict, every file the compared
// side changed since they met, and merge or rebase between them.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitCompareView: View {
    @Environment(\.gitStyle) private var style
    private let context: GitDialogContext
    @Binding private var base: String
    @Binding private var compare: String
    @State private var model = CompareModel()
    @State private var pendingAction: CompareAction?
    @State private var isActing = false
    @State private var showsCompare = true
    @State private var showsBase = true
    @State private var showsFiles = true
    @State private var expanded: Set<String> = []
    private let diffOptions = HistoryDiffOptions()

    enum CompareAction { case merge, rebase }

    /// - Parameters:
    ///   - context: Reads through its repository and refs; merge and rebase run through its commands.
    ///   - base: A branch, tag or commit; empty until picked.
    public init(context: GitDialogContext, base: Binding<String>, compare: Binding<String>) {
        self.context = context
        _base = base
        _compare = compare
    }

    public var body: some View {
        VStack(spacing: 0) {
            CompareRefBar(refs: context.refs, base: $base, compare: $compare, model: model)
            if let error = model.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: error, tone: .negative, onDismiss: { model.errorMessage = nil })
                    .padding(GitMetrics.Spacing.sm)
            }
            content
            if !base.isEmpty, !compare.isEmpty, model.comparison?.onlyInCompare.isEmpty == false {
                actionBar
            }
        }
        .gitPanel()
        .task(id: "\(base)...\(compare)") {
            await context.refs.loadIfNeeded()
            await model.load(context.repository, base: base, compare: compare)
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { pendingAction != nil },
                                                                    set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction == .rebase ? "Rebase" : "Merge", role: pendingAction == .rebase ? .destructive : nil) {
                let action = pendingAction
                Task { await perform(action) }
            }
        } message: {
            Text(pendingAction == .rebase ? "Rewrites \(compare)'s commits. Only rebase branches you haven't shared."
                 : "Merges \(compare) into the checked-out branch.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if base.isEmpty || compare.isEmpty {
            GitEmptyState(systemImage: "arrow.left.arrow.right", title: "Choose Two Refs",
                          subtitle: "See which commits each branch, tag or commit has that the other doesn't.")
        } else if model.comparison == nil, model.isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isIdentical {
            GitEmptyState(systemImage: "checkmark.circle", title: "Refs Match", subtitle: "\(base) and \(compare) have the same commits.")
        } else if let comparison = model.comparison {
            list(comparison)
        } else {
            Spacer()
        }
    }

    private func list(_ comparison: BranchComparison) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CompareSectionHeader(title: "Only in \(compare)", symbol: "arrow.right", count: comparison.onlyInCompare.count,
                                     isExpanded: $showsCompare)
                if showsCompare { ForEach(comparison.onlyInCompare) { CompareCommitRow(commit: $0) } }
                CompareSectionHeader(title: "Only in \(base)", symbol: "arrow.left", count: comparison.onlyInBase.count,
                                     isExpanded: $showsBase)
                if showsBase { ForEach(comparison.onlyInBase) { CompareCommitRow(commit: $0) } }
                CompareSectionHeader(title: "Files changed in \(compare)", symbol: "doc",
                                     count: model.isLoadingFiles ? comparison.files.count : model.files.count,
                                     isExpanded: $showsFiles) {
                    if showsFiles, !model.files.isEmpty { HistoryDiffToggles(options: diffOptions.options) }
                }
                if showsFiles { files }
            }
            .padding(.bottom, GitMetrics.Spacing.sm)
        }
    }

    @ViewBuilder
    private var files: some View {
        if model.isLoadingFiles {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(GitMetrics.Spacing.md)
        } else {
            CompareFiles(context: context, files: model.files, expanded: $expanded, options: diffOptions.options,
                         old: model.preview.mergeBase ?? base, base: base, compare: compare)
        }
    }

    private var actionBar: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if isActing { ProgressView().controlSize(.small) }
            Spacer()
            Button { pendingAction = .rebase } label: { Label("Rebase \(compare) onto \(base)", systemImage: "arrow.triangle.branch") }
                .requires(.rebase)
                .gitClickable()
            Button { pendingAction = .merge } label: { Label("Merge into \(base)", systemImage: "arrow.triangle.merge") }
                .buttonStyle(.borderedProminent)
                .requires(.merge)
                .gitClickable()
        }
        .disabled(isActing)
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .frame(height: 48 * style.fontScale)
        .overlay(alignment: .top) { Rectangle().fill(style.border).frame(height: 0.5) }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .rebase: "Rebase \(compare) onto \(base)?"
        case .merge: "Merge \(compare) into \(base)?"
        case nil: ""
        }
    }

    /// Merge and rebase act on the checked-out branch, so the matching side has to be it.
    private func perform(_ action: CompareAction?) async {
        guard let action else { return }
        let head = context.headBranch?.name
        isActing = true
        defer { isActing = false }
        do {
            switch action {
            case .merge:
                guard head == base else { return model.errorMessage = "Check out \(base) first to merge \(compare) into it." }
                try await context.commands.perform(.merge(compare, squash: false))
            case .rebase:
                guard head == compare else { return model.errorMessage = "Check out \(compare) first to rebase it onto \(base)." }
                try await context.commands.perform(.rebase(onto: base))
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
        // A conflicted merge or rebase still changes the repository.
        await context.onChange?()
        await model.load(context.repository, base: base, compare: compare)
    }
}

/// The kit's own comparison, for a sheet: it keeps the two refs itself.
struct CompareSheetContent: View {
    let context: GitDialogContext
    @State var base: String
    @State var compare: String

    var body: some View {
        GitCompareView(context: context, base: $base, compare: $compare)
    }
}
#endif
