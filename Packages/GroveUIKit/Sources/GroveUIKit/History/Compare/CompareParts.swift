// History/Compare/CompareParts.swift
// GroveUIKit
//
// The comparison's ref pickers and summary, its section headers, commit rows and files.

#if os(macOS)
import GroveKit
import SwiftUI

/// Base, swap and compare, with what the comparison found.
struct CompareRefBar: View {
    @Environment(\.gitStyle) private var style
    let refs: RepositoryRefs
    @Binding var base: String
    @Binding var compare: String
    let model: CompareModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                picker("Base", selection: $base)
                Button { swap(&base, &compare) } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless)
                    .gitClickable()
                    .foregroundStyle(style.textSecondary)
                    .help("Swap sides")
                    .accessibilityLabel("Swap sides")
                    .disabled(base.isEmpty || compare.isEmpty)
                picker("Compare", selection: $compare)
                Spacer()
                if model.isLoading || model.isLoadingFiles { ProgressView().controlSize(.mini) }
                if let comparison = model.comparison { counts(comparison) }
            }
            .padding(.horizontal, GitMetrics.Spacing.lg)
            .frame(height: 48 * style.fontScale)
            if model.comparison != nil { mergeSummary }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }
    }

    private func counts(_ comparison: BranchComparison) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Label("\(comparison.onlyInBase.count)", systemImage: "arrow.left").help("Commits only in \(base)")
            Label("\(comparison.onlyInCompare.count)", systemImage: "arrow.right").help("Commits only in \(compare)")
            if comparison.equivalentCount > 0 {
                Label("\(comparison.equivalentCount)", systemImage: "equal").help("Commits with the same patch on both sides")
            }
            Label("\(comparison.files.count)", systemImage: "doc").help("Files changed in \(compare) since the merge base")
        }
        .font(style.monoCaption)
        .foregroundStyle(style.textSecondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var mergeSummary: some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            if let mergeBase = model.preview.mergeBase {
                Text("merge base \(String(mergeBase.prefix(7)))").font(style.monoCaption).foregroundStyle(style.textSecondary)
            }
            Spacer()
            switch model.preview.conflicts {
            case true?:
                Label("Would conflict", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(style.warning)
                    .help("Merging \(compare) into \(base) would conflict")
            case false?:
                Label("Merges cleanly", systemImage: "checkmark.circle.fill").foregroundStyle(style.success)
            case nil:
                EmptyView()
            }
        }
        .font(style.font(12))
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .padding(.bottom, GitMetrics.Spacing.sm)
    }

    /// Branches, remote branches and tags; a commit that's none of them shows by its short SHA.
    private func picker(_ title: String, selection: Binding<String>) -> some View {
        let locals = refs.localBranches.map(\.name)
        let remotes = refs.remoteBranches.filter { !$0.id.hasSuffix("/HEAD") }.map(\.name)
        let tags = refs.tags.map(\.name)
        let value = selection.wrappedValue
        return Picker(title, selection: selection) {
            if value.isEmpty { Text("Choose").tag("") }
            if !value.isEmpty, !(locals + remotes + tags).contains(value) {
                Text(value.count == 40 ? String(value.prefix(7)) : value).tag(value)
            }
            Section("Branches") { ForEach(locals, id: \.self) { Text($0).tag($0) } }
            if !remotes.isEmpty { Section("Remote") { ForEach(remotes, id: \.self) { Text($0).tag($0) } } }
            if !tags.isEmpty { Section("Tags") { ForEach(tags, id: \.self) { Text($0).tag($0) } } }
        }
        .font(style.font(13))
        .frame(maxWidth: 240 * style.fontScale)
        .gitClickable()
        .accessibilityLabel(title)
    }
}

/// Collapsible, so a long side doesn't bury the other.
struct CompareSectionHeader<Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    let title: String
    let symbol: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: GitMetrics.Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(style.font(9, .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(style.textSecondary)
                    Image(systemName: symbol)
                        .font(style.font(11, .semibold))
                        .foregroundStyle(style.textSecondary)
                    GitSectionLabel(title: title, count: count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gitClickable()
            Spacer()
            accessory()
        }
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .padding(.top, GitMetrics.Spacing.md)
        .padding(.bottom, GitMetrics.Spacing.xs)
    }
}

extension CompareSectionHeader where Accessory == EmptyView {
    init(title: String, symbol: String, count: Int, isExpanded: Binding<Bool>) {
        self.init(title: title, symbol: symbol, count: count, isExpanded: isExpanded) { EmptyView() }
    }
}

struct CompareCommitRow: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var uiHost
    @Environment(\.historyHost) private var host
    let commit: CommitInfo

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            CommitAvatar(name: commit.authorName, email: commit.authorEmail, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(style.font(13, .medium)).foregroundStyle(style.textPrimary).lineLimit(1)
                Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if commit.isMerge {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(style.textSecondary).accessibilityLabel("Merge commit")
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .frame(height: 44 * style.fontScale)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { host.showInHistory?(commit.id) }
        .contextMenu {
            if let show = host.showInHistory { Button("Show in History") { show(commit.id) } }
            Button("Copy Commit SHA") {
                uiHost.copy(commit.id)
                uiHost.toast("Copied SHA")
            }
        }
    }
}

/// The compared side's files, each opening into its diff since the merge base.
struct CompareFiles: View {
    @Environment(\.historyHost) private var host
    @Environment(\.gitHost) private var uiHost
    let context: GitDialogContext
    let files: [FileDiff]
    @Binding var expanded: Set<String>
    let options: GitDiffOptions
    let old: String
    let base: String
    let compare: String

    var body: some View {
        if files.isEmpty {
            GitEmptyState(systemImage: "doc", title: "No File Changes", subtitle: "\(compare) changes no files since the merge base.")
                .frame(height: 160)
        } else {
            ChangesetFiles(
                files: files, expanded: expanded,
                toggle: { path in if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) } },
                options: options,
                images: GitDiffImages(repository: context.repository, old: .commit(old), new: .commit(compare)),
                annotations: host.compareAnnotations.map { annotate in { annotate($0, base, compare) } },
                menu: { path in
                    AnyView(Group {
                        if let blame = host.openBlame { Button("Open Blame at \(compare)") { blame(path, compare) } }
                        Button("Copy Path") {
                            uiHost.copy(path)
                            uiHost.toast("Copied path")
                        }
                    })
                })
        }
    }
}
#endif
