// Views/History/BranchComparisonView.swift
// Grove

import GroveKit
import SwiftUI

/// Both sides of `base...compare`: commits only in each branch, plus the files `compare` changed, with Merge / Rebase actions.
struct BranchComparisonView: View {
    let repository: any GitRepositoryProtocol
    /// The session's shared refs; without them (previews) the branches are read directly.
    var refs: RepositoryRefs?
    var initialTarget: BranchInfo?
    var onRepositoryChanged: (() async -> Void)?

    @State private var branches: [BranchInfo] = []
    @State private var source: BranchInfo?
    @State private var target: BranchInfo?
    @State private var comparison = BranchComparison()
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?
    @State private var pendingAction: ComparisonAction?
    @State private var showsTarget = true
    @State private var showsSource = true
    @State private var showsFiles = false

    private enum ComparisonAction { case merge, rebase }

    private var isIdentical: Bool {
        comparison.onlyInBase.isEmpty && comparison.onlyInCompare.isEmpty && comparison.files.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerBar
            if let errorMessage {
                Banner(symbol: "xmark.octagon", message: errorMessage, tone: .negative,
                       onDismiss: { self.errorMessage = nil })
                    .padding(Theme.Spacing.sm)
            }
            content
            if let source, let target, !comparison.onlyInCompare.isEmpty {
                actionBar(source: source, target: target)
            }
        }
        .panel()
        .task { await loadBranches() }
        .onChange(of: source) { Task { await compare() } }
        .onChange(of: target) { Task { await compare() } }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction == .rebase ? "Rebase" : "Merge", role: pendingAction == .rebase ? .destructive : nil) {
                let action = pendingAction
                Task { await perform(action) }
            }
        } message: {
            Text(pendingAction == .rebase
                 ? "Rewrites \(target?.name ?? "the branch")'s commits. Only rebase branches you haven't shared."
                 : "Merges \(target?.name ?? "the branch") into the checked-out branch.")
        }
    }

    // MARK: - Sections

    private var pickerBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            branchPicker("Base", selection: $source)
            Button { swap(&source, &target) } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.textSecondary)
                .help("Swap branches")
            branchPicker("Compare", selection: $target)
            Spacer()
            if source != nil, target != nil, !isLoading {
                countsSummary
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    private var countsSummary: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label("\(comparison.onlyInBase.count)", systemImage: "arrow.left")
                .help("Commits only in \(source?.name ?? "base")")
            Label("\(comparison.onlyInCompare.count)", systemImage: "arrow.right")
                .help("Commits only in \(target?.name ?? "compare")")
            if comparison.equivalentCount > 0 {
                Label("\(comparison.equivalentCount)", systemImage: "equal")
                    .help("Commits with the same patch on both sides")
            }
            Label("\(comparison.files.count)", systemImage: "doc")
                .help("Files changed in \(target?.name ?? "compare") since the merge base")
        }
        .font(.monoCaption)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }

    private func branchPicker(_ label: String, selection: Binding<BranchInfo?>) -> some View {
        Picker(label, selection: selection) {
            Text("Choose\u{2026}").tag(BranchInfo?.none)
            ForEach(branches) { Text($0.name).tag(Optional($0)) }
        }
        .font(.system(size: 13))
        .frame(maxWidth: 240)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let source, let target {
            if isIdentical {
                EmptyStateView(systemImage: "checkmark.circle", title: "Branches Match",
                               subtitle: "\(source.name) and \(target.name) have the same commits.")
            } else {
                comparisonList(source: source, target: target)
            }
        } else {
            EmptyStateView(systemImage: "arrow.left.arrow.right", title: "Choose Two Branches",
                           subtitle: "See which commits each branch has that the other doesn't.")
        }
    }

    private func comparisonList(source: BranchInfo, target: BranchInfo) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ComparisonSectionHeader(title: "Only in \(target.name)", symbol: "arrow.right",
                                        count: comparison.onlyInCompare.count, isExpanded: $showsTarget)
                if showsTarget { ForEach(comparison.onlyInCompare) { ComparisonCommitRow(commit: $0) } }
                ComparisonSectionHeader(title: "Only in \(source.name)", symbol: "arrow.left",
                                        count: comparison.onlyInBase.count, isExpanded: $showsSource)
                if showsSource { ForEach(comparison.onlyInBase) { ComparisonCommitRow(commit: $0) } }
                ComparisonSectionHeader(title: "Files changed in \(target.name)", symbol: "doc",
                                        count: comparison.files.count, isExpanded: $showsFiles)
                if showsFiles { ForEach(comparison.files) { ComparisonFileRow(file: $0) } }
            }
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    private func actionBar(source: BranchInfo, target: BranchInfo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isActing { ProgressView().controlSize(.small) }
            Spacer()
            Button { pendingAction = .rebase } label: { Label("Rebase \(target.name) onto \(source.name)", systemImage: "arrow.triangle.branch") }
            Button { pendingAction = .merge } label: { Label("Merge into \(source.name)", systemImage: "arrow.triangle.merge") }
                .buttonStyle(.borderedProminent)
        }
        .disabled(isActing)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .rebase: "Rebase \(target?.name ?? "") onto \(source?.name ?? "")?"
        case .merge: "Merge \(target?.name ?? "") into \(source?.name ?? "")?"
        case nil: ""
        }
    }

    // MARK: - Git

    private func loadBranches() async {
        do {
            let (l, r) = try await readBranches()
            branches = l + r.filter { !$0.id.hasSuffix("/HEAD") }
            source = l.first(where: \.isHEAD) ?? l.first
            if let initialTarget { target = branches.first { $0.id == initialTarget.id } ?? initialTarget }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readBranches() async throws -> (local: [BranchInfo], remote: [BranchInfo]) {
        guard let refs else {
            async let local = repository.localBranches()
            async let remote = repository.remoteBranches()
            return try await (local, remote)
        }
        await refs.loadIfNeeded()
        return (refs.localBranches, refs.remoteBranches)
    }

    private func compare() async {
        guard let source, let target, source.id != target.id else { return comparison = BranchComparison() }
        isLoading = true
        defer { isLoading = false }
        do {
            comparison = try await repository.compareBranches(base: source.name, compare: target.name)
        } catch {
            errorMessage = error.localizedDescription
            comparison = BranchComparison()
        }
    }

    private func perform(_ action: ComparisonAction?) async {
        guard let action, let source, let target else { return }
        isActing = true
        defer { isActing = false }
        do {
            // Merge and rebase act on the checked-out branch, so the matching side must be HEAD.
            switch action {
            case .merge:
                guard source.isHEAD else {
                    errorMessage = "Check out \(source.name) first to merge \(target.name) into it."
                    return
                }
                try await repository.merge(branch: target.name)
            case .rebase:
                guard target.isHEAD else {
                    errorMessage = "Check out \(target.name) first to rebase it onto \(source.name)."
                    return
                }
                try await repository.rebase(onto: source.name)
            }
            await onRepositoryChanged?()
            await compare()
        } catch {
            errorMessage = error.localizedDescription
            // A conflicted merge or rebase still changes the repository.
            await onRepositoryChanged?()
        }
    }
}

#Preview {
    BranchComparisonView(repository: MockGitRepository())
        .frame(width: 720, height: 480)
        .padding()
        .background(Theme.background)
}
