// Views/WorkingCopy/CommitIdentityMenu.swift
// Grove
//
// Who the next commit is authored as, with a menu to switch this repository to another profile.

import GroveKit
import SwiftUI

struct CommitIdentityMenu: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    private let store = UserProfileStore.shared

    var body: some View {
        Menu {
            Section("Commit As") {
                ForEach(store.profiles) { profile in
                    Button {
                        Task { await viewModel.switchIdentity(to: profile) }
                    } label: {
                        Label("\(profile.title) \u{2014} \(profile.email)",
                              systemImage: profile.matches(viewModel.identity) ? "checkmark" : "person.crop.circle")
                    }
                }
            }
            Divider()
            SettingsLink { Text(store.profiles.isEmpty ? "Add a Profile in Settings…" : "Manage Profiles…") }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let identity = viewModel.identity {
                InitialAvatar(name: identity.name, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(identity.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        if let profile = store.profile(matching: identity), !profile.label.isEmpty {
                            Text(profile.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text(identity.email)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
            } else {
                Label("No git identity", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .contentShape(Rectangle())
    }

    private var help: String {
        guard let identity = viewModel.identity else { return "Set user.name and user.email, or choose a profile" }
        return "Committing as \(identity.name) <\(identity.email)>. Click to switch this repository to another profile."
    }
}

#Preview {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    CommitIdentityMenu()
        .environment(vm)
        .padding()
        .background(Theme.surface)
        .task { await vm.refresh() }
}
