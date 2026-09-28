// Views/History/BranchComparisonView.swift
// Grove

import AppKit
import SwiftUI

/// Commits in `target` that aren't in `source` (`git log source..target`), with Merge / Rebase actions.
struct BranchComparisonView: View {
    let repository: any GitRepositoryProtocol
    var initialTarget: BranchInfo?

    @State private var branches: [BranchInfo] = []
    @State private var source: BranchInfo?
    @State private var target: BranchInfo?
    @State private var commits: [CommitInfo] = []
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?
    @State private var pendingAction: ComparisonAction?

    private enum ComparisonAction { case merge, rebase }

    var body: some View {
        VStack(spacing: 0) {
            pickerBar
            if let errorMessage {
                Banner(symbol: "xmark.octagon", message: errorMessage, tone: .negative,
                       onDismiss: { self.errorMessage = nil })
                    .padding(Theme.Spacing.sm)
            }
            content
            if let source, let target, !commits.isEmpty {
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
            if let source, let target, !commits.isEmpty {
                Text("\(commits.count) commit\(commits.count == 1 ? "" : "s") in \(target.name) not in \(source.name)")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
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
        } else if source == nil || target == nil {
            EmptyStateView(systemImage: "arrow.left.arrow.right", title: "Choose Two Branches",
                           subtitle: "See which commits one branch has that the other doesn't.")
        } else if commits.isEmpty {
            EmptyStateView(systemImage: "checkmark.circle", title: "Nothing to Bring Over",
                           subtitle: "\(target?.name ?? "") has no commits that \(source?.name ?? "") lacks.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commits) { ComparisonCommitRow(commit: $0) }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
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
            async let local = repository.localBranches()
            async let remote = repository.remoteBranches()
            let (l, r) = try await (local, remote)
            branches = l + r.filter { !$0.id.hasSuffix("/HEAD") }
            source = l.first(where: \.isHEAD) ?? l.first
            if let initialTarget { target = branches.first { $0.id == initialTarget.id } ?? initialTarget }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compare() async {
        guard let source, let target, source.id != target.id else { return commits = [] }
        isLoading = true
        defer { isLoading = false }
        do {
            commits = try await repository.log(maxCount: 500, skip: 0, branch: "\(source.name)..\(target.name)")
        } catch {
            errorMessage = error.localizedDescription
            commits = []
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
            await compare()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComparisonCommitRow: View {
    let commit: CommitInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AvatarView(name: commit.authorName, email: commit.authorEmail, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(.rowTitle).lineLimit(1)
                Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if commit.isMerge {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 44)
        .contextMenu {
            Button("Copy Commit SHA") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.id, forType: .string)
            }
        }
    }
}

#Preview {
    BranchComparisonView(repository: MockGitRepository())
        .frame(width: 720, height: 480)
        .padding()
        .background(Theme.background)
}
