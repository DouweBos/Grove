// Views/Dialogs/PullSourcePicker.swift
// Grove

import SwiftUI

/// Which remote branch to pull from: the upstream by default, or e.g. `origin/main` to rebase onto it.
struct PullSourcePicker: View {
    let branches: [BranchInfo]
    let upstream: String?
    @Binding var selection: String?

    /// Branch names teams usually integrate from, in the order they're suggested.
    private static let mainlineNames = ["main", "master", "develop", "trunk"]

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
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "cloud")
                Text(selection ?? "Choose a remote branch").font(.monoCaption).lineLimit(1).truncationMode(.middle)
                if let selection, selection == upstream {
                    Text("upstream").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .fixedSize()
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
        name == upstream ? "\(name)  (upstream)" : name
    }

    private var names: [String] {
        branches.map(\.name).filter { !$0.hasSuffix("/HEAD") }
    }

    /// The upstream, then each remote's mainline branch.
    private var suggested: [String] {
        var result: [String] = upstream.map { [$0] } ?? []
        for group in byRemote {
            if let mainline = Self.mainlineNames.lazy.map({ "\(group.remote)/\($0)" }).first(where: group.names.contains),
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

    /// The default choice: the upstream, else a same-named remote branch, else the first remote's mainline.
    static func defaultSource(for branch: BranchInfo?, in branches: [BranchInfo]) -> String? {
        if let upstream = branch?.upstreamShortName { return upstream }
        let names = Set(branches.map(\.name))
        if let branch, let twin = names.sorted().first(where: { $0.hasSuffix("/" + branch.name) }) { return twin }
        for mainline in mainlineNames {
            if let match = names.sorted().first(where: { $0.hasSuffix("/" + mainline) && $0.split(separator: "/").count == 2 }) {
                return match
            }
        }
        return nil
    }
}
