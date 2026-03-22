// Views/History/BranchComparisonView.swift
// Grove

import SwiftUI

// MARK: - BranchComparisonView

/// A view that shows the commits that differ between two branches.
///
/// Equivalent to `git log source..target` — commits reachable from `target`
/// that are not reachable from `source`.
///
/// Displays ahead/behind statistics at the top, a commit list in the middle,
/// and Merge / Rebase action buttons at the bottom.
struct BranchComparisonView: View {

    // MARK: - State

    /// All local branches available to pick from.
    @State private var availableBranches: [BranchInfo] = []
    /// The branch used as the base (left side of the `..` range).
    @State private var sourceBranch: BranchInfo?
    /// The branch being compared against the source.
    @State private var targetBranch: BranchInfo?
    /// Commits in `target` but not in `source`.
    @State private var commits: [CommitInfo] = []
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?
    @State private var actionConfirmation: ActionConfirmation?

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            branchPickerBar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Comparing branches\u{2026}")
                    .padding()
                Spacer()
            } else if let error = errorMessage {
                errorState(error)
            } else if sourceBranch == nil || targetBranch == nil {
                promptState
            } else if commits.isEmpty {
                identicalState
            } else {
                commitListSection
            }

            if sourceBranch != nil && targetBranch != nil && !commits.isEmpty {
                Divider()
                actionBar
            }
        }
        .task {
            await loadBranches()
        }
        .alert("Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            actionConfirmation?.title ?? "",
            isPresented: Binding(
                get: { actionConfirmation != nil },
                set: { if !$0 { actionConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation = actionConfirmation {
                Button(confirmation.actionLabel, role: confirmation.isDestructive ? .destructive : nil) {
                    Task { await confirmation.action() }
                    actionConfirmation = nil
                }
                Button("Cancel", role: .cancel) {
                    actionConfirmation = nil
                }
            }
        } message: {
            Text(actionConfirmation?.message ?? "")
        }
    }

    // MARK: - Branch Picker Bar

    private var branchPickerBar: some View {
        HStack(spacing: 12) {
            // Source branch picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Source", selection: $sourceBranch) {
                    Text("Choose branch\u{2026}").tag(BranchInfo?.none)
                    ForEach(availableBranches) { branch in
                        Text(branch.name).tag(Optional(branch))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 160)
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            // Target branch picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Target (compare)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Target", selection: $targetBranch) {
                    Text("Choose branch\u{2026}").tag(BranchInfo?.none)
                    ForEach(availableBranches) { branch in
                        Text(branch.name).tag(Optional(branch))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 160)
            }

            Spacer()

            // Ahead/behind statistics pill
            if !commits.isEmpty, let source = sourceBranch, let target = targetBranch {
                aheadBehindStats(source: source, target: target)
            }

            Button {
                Task { await compare() }
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered)
            .disabled(sourceBranch == nil || targetBranch == nil || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .onChange(of: sourceBranch) { _, _ in Task { await compare() } }
        .onChange(of: targetBranch) { _, _ in Task { await compare() } }
    }

    @ViewBuilder
    private func aheadBehindStats(source: BranchInfo, target: BranchInfo) -> some View {
        HStack(spacing: 6) {
            // Use the target branch's ahead count if it refers to source,
            // otherwise show the commit count as "N ahead".
            let ahead = commits.count
            let behind = target.behind > 0 ? target.behind : 0

            Label("\(ahead) ahead", systemImage: "arrow.up.circle.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)

            if behind > 0 {
                Label("\(behind) behind", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Commit List

    private var commitListSection: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                if let target = targetBranch, let source = sourceBranch {
                    Text("\(commits.count) commit\(commits.count == 1 ? "" : "s") in ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    + Text(target.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    + Text(" not in ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    + Text(source.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            List(commits, id: \.id) { commit in
                ComparisonCommitRow(commit: commit)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                guard let source = sourceBranch else { return }
                actionConfirmation = ActionConfirmation(
                    title: "Merge \(targetBranch?.name ?? "") into \(source.name)",
                    message: "This will merge the commits from \(targetBranch?.name ?? "target") into \(source.name). This operation cannot be undone automatically.",
                    actionLabel: "Merge",
                    isDestructive: false,
                    action: { await performMerge() }
                )
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.bordered)
            .disabled(isActing)

            Button {
                guard let source = sourceBranch else { return }
                actionConfirmation = ActionConfirmation(
                    title: "Rebase \(targetBranch?.name ?? "") onto \(source.name)",
                    message: "This rewrites history on \(targetBranch?.name ?? "target"). Only rebase branches that have not been shared with others.",
                    actionLabel: "Rebase",
                    isDestructive: true,
                    action: { await performRebase() }
                )
            } label: {
                Label("Rebase", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .disabled(isActing)

            if isActing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Empty / Prompt States

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Select two branches to compare")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identicalState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Branches are identical")
                .fontWeight(.medium)
            if let source = sourceBranch, let target = targetBranch {
                Text("\(target.name) has no commits that \(source.name) does not already contain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
            Text("Comparison failed")
                .fontWeight(.medium)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Retry") {
                Task { await compare() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func loadBranches() async {
        do {
            async let local = repository.localBranches()
            async let remote = repository.remoteBranches()
            let (localBranches, remoteBranches) = try await (local, remote)
            availableBranches = localBranches + remoteBranches
            // Auto-select HEAD as source
            sourceBranch = localBranches.first(where: { $0.isHEAD }) ?? localBranches.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compare() async {
        guard let source = sourceBranch, let target = targetBranch else {
            commits = []
            return
        }
        guard source.id != target.id else {
            commits = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Fetch commits reachable from target but not from source.
            // Use the branch filter `source..target` format.
            commits = try await repository.log(
                maxCount: 500,
                skip: 0,
                branch: "\(source.name)..\(target.name)"
            )
        } catch {
            errorMessage = error.localizedDescription
            commits = []
        }
    }

    private func performMerge() async {
        guard let target = targetBranch else { return }
        isActing = true
        errorMessage = nil
        defer { isActing = false }
        do {
            try await repository.merge(branch: target.name)
            await compare()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRebase() async {
        guard let source = sourceBranch else { return }
        isActing = true
        errorMessage = nil
        defer { isActing = false }
        do {
            try await repository.rebase(onto: source.name)
            await compare()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ActionConfirmation

/// Encapsulates the data needed to present a confirmation dialog for a destructive action.
private struct ActionConfirmation {
    let title: String
    let message: String
    let actionLabel: String
    let isDestructive: Bool
    let action: () async -> Void
}

// MARK: - ComparisonCommitRow

/// A compact commit row for the branch comparison list.
///
/// Simpler than ``CommitRow`` — no graph lane, no tag pills —
/// since the comparison context makes those unnecessary.
private struct ComparisonCommitRow: View {

    let commit: CommitInfo

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Dot indicator
            Circle()
                .fill(commit.isMerge ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{B7}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(commit.authorDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if commit.isMerge {
                        Image(systemName: "arrow.triangle.merge")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    if commit.isSigned {
                        Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Text(commit.shortSHA)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Commit SHA") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.id, forType: .string)
            }
            Button("Copy Short SHA") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.shortSHA, forType: .string)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BranchComparisonView(repository: MockGitRepository())
        .frame(width: 680, height: 500)
        .task { }
}
