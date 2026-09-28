// Views/Settings/ProfilesPreferencesTab.swift
// Grove
//
// Named identities (name, email, signing key) to pick per repository.

import SwiftUI

struct ProfilesPreferencesTab: View {

    private let store = UserProfileStore.shared
    @State private var selection: UserProfile.ID?

    private var selected: UserProfile? { store.profiles.first { $0.id == selection } }

    var body: some View {
        Form {
            Section {
                if store.profiles.isEmpty {
                    Text("No profiles yet. Add one for each identity you commit as, e.g. Work and Personal.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(store.profiles) { row($0) }
                HStack {
                    Button("Add Profile", systemImage: "plus") { selection = store.add().id }
                    Button("Remove", systemImage: "minus") {
                        if let selection { store.delete(id: selection) }
                        selection = nil
                    }
                    .disabled(selected == nil)
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Pick a profile in a repository's Settings or from the identity above the Commit button. "
                     + "It's written to that repository's .git/config only.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            if let profile = selected {
                Section("Edit \u{201C}\(profile.title)\u{201D}") {
                    TextField("Label", text: binding(profile, \.label), prompt: Text("Work"))
                    TextField("Name", text: binding(profile, \.userName), prompt: Text("Your Name"))
                    TextField("Email", text: binding(profile, \.email), prompt: Text("you@example.com"))
                    TextField("Signing Key", text: binding(profile, \.signingKey), prompt: Text("Use global setting"))
                        .font(.monoCaption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ profile: UserProfile) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            InitialAvatar(name: profile.userName.isEmpty ? profile.title : profile.userName, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(profile.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Text(profile.email.isEmpty ? "No email" : profile.email).font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !profile.signingKey.isEmpty {
                Image(systemName: "signature").foregroundStyle(Theme.textSecondary).help("Signs with \(profile.signingKey)")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(selection == profile.id ? Theme.selectionFill : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .padding(.horizontal, -Theme.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { selection = profile.id }
    }

    private func binding(_ profile: UserProfile, _ keyPath: WritableKeyPath<UserProfile, String>) -> Binding<String> {
        Binding(get: { selected?[keyPath: keyPath] ?? "" }, set: { value in
            var updated = selected ?? profile
            updated[keyPath: keyPath] = value
            store.update(updated)
        })
    }
}

#Preview {
    ProfilesPreferencesTab().frame(width: 560, height: 520)
}
