// Dialogs/Views/PullSourcePicker.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Which remote branch to pull from: the upstream by default, or e.g. `origin/main` to rebase onto it.
struct PullSourcePicker: View {
    @Environment(\.gitStyle) private var style
    let branches: [BranchInfo]
    let upstream: String?
    /// Parent recorded when the branch was created; suggested both as its remote branch and locally.
    var parent: String?
    /// The app's usual pick, suggested after the upstream.
    var preferred: String?
    @Binding var selection: String?
    /// Switches to typing a branch that isn't in the list, e.g. one not fetched yet.
    var typeOther: (() -> Void)?

    /// Local sources are written `./branch`: `git pull . branch` integrates a local branch.
    nonisolated static func localSource(_ branch: String) -> String { "./" + branch }

    nonisolated static func displayName(_ source: String) -> String {
        source.hasPrefix("./") ? String(source.dropFirst(2)) + " (local)" : source
    }

    var body: some View {
        Menu {
            if !suggested.isEmpty {
                Section("Suggested") {
                    ForEach(suggested, id: \.self) { item($0) }
                }
            }
            Section("All Remote Branches") {
                ForEach(byRemote, id: \.remote) { group in
                    Menu(group.remote) {
                        ForEach(group.names, id: \.self) { item($0) }
                    }
                }
            }
            if let typeOther {
                Divider()
                Button("Other Branch", action: typeOther)
            }
        } label: {
            HStack(spacing: GitMetrics.Spacing.xs) {
                Image(systemName: "cloud")
                Text(selection.map(Self.displayName) ?? "Choose a remote branch")
                    .font(style.monoCaption).lineLimit(1).truncationMode(.middle)
                if let selection, selection == upstream {
                    Text("upstream").font(style.font(11)).foregroundStyle(style.textSecondary)
                }
            }
        }
        .gitClickable()
        // Truncates rather than widening the dialog past the sheet for a long branch name.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func item(_ name: String) -> some View {
        Button {
            selection = name
        } label: {
            if name == selection {
                Label(title(name), systemImage: "checkmark")
            } else {
                Text(title(name))
            }
        }
    }

    private func title(_ name: String) -> String {
        if name == upstream { return "\(name)  (upstream)" }
        if parentSources.contains(name) { return "\(Self.displayName(name))  (parent)" }
        return name
    }

    /// Remote branches named `branch`, then the local branch itself.
    private func sources(named branch: String?) -> [String] {
        guard let branch else { return [] }
        return names.filter { $0.split(separator: "/", maxSplits: 1).last.map(String.init) == branch } + [Self.localSource(branch)]
    }

    private var parentSources: [String] { sources(named: parent) }

    var names: [String] {
        branches.map(\.name).filter { !$0.hasSuffix("/HEAD") }
    }

    /// The upstream, the parent, the app's pick, then each remote's mainline branch.
    private var suggested: [String] {
        var result: [String] = upstream.map { [$0] } ?? []
        for source in parentSources + sources(named: preferred).filter({ !$0.hasPrefix("./") }) where !result.contains(source) {
            result.append(source)
        }
        for group in byRemote {
            if let mainline = GitPullForm.mainlineNames.lazy.map({ "\(group.remote)/\($0)" }).first(where: group.names.contains),
               !result.contains(mainline) {
                result.append(mainline)
            }
        }
        return result
    }

    private var byRemote: [(remote: String, names: [String])] {
        Dictionary(grouping: names) { $0.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0 }
            .map { (remote: $0.key, names: $0.value.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) }
            .sorted { $0.remote < $1.remote }
    }
}
#endif
