// Views/Settings/UserProfilesPreferencesTab.swift
// Grove
//
// User profiles preferences: named author identities with optional GPG/SSH signing keys.

import SwiftUI

// MARK: - PreferencesUserProfile Model

/// A named git author identity used for per-commit author selection.
struct PreferencesUserProfile: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var email: String
    var signingKeyID: String
    var isDefault: Bool
}

// MARK: - UserProfilesPreferencesTab

/// Preferences tab for managing multiple git author profiles.
struct UserProfilesPreferencesTab: View {

    @State private var profiles: [PreferencesUserProfile] = [
        PreferencesUserProfile(name: "Your Name", email: "you@example.com", signingKeyID: "", isDefault: true)
    ]
    @State private var selectedProfileID: PreferencesUserProfile.ID?

    private var selectedProfile: Binding<PreferencesUserProfile>? {
        guard let id = selectedProfileID,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return $profiles[index]
    }

    var body: some View {
        HSplitView {
            profileList
                .frame(minWidth: 180, maxWidth: 220)

            if let profile = selectedProfile {
                profileDetail(profile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Profile List

    @ViewBuilder
    private var profileList: some View {
        VStack(spacing: 0) {
            List(profiles, selection: $selectedProfileID) { profile in
                ProfileRow(profile: profile)
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 0) {
                Button {
                    addProfile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)

                Button {
                    removeSelectedProfile()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selectedProfileID == nil || profiles.count <= 1)

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
        }
    }

    // MARK: - Profile Detail

    @ViewBuilder
    private func profileDetail(_ profile: Binding<PreferencesUserProfile>) -> some View {
        Form {
            Section("Identity") {
                LabeledContent("Name") {
                    TextField("Full Name", text: profile.name)
                }
                LabeledContent("Email") {
                    TextField("email@example.com", text: profile.email)
                        .textContentType(.emailAddress)
                }
            }

            Section("Signing") {
                LabeledContent("GPG / SSH Key ID") {
                    TextField("Optional key fingerprint or path", text: profile.signingKeyID)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Default") {
                Toggle("Use as default profile", isOn: profile.isDefault)
                    .onChange(of: profile.wrappedValue.isDefault) { _, newValue in
                        if newValue {
                            clearOtherDefaults(except: profile.wrappedValue.id)
                        }
                    }
                Text("The default profile is pre-selected in the commit dialog.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Empty Detail

    @ViewBuilder
    private var emptyDetail: some View {
        ContentUnavailableView(
            "No Profile Selected",
            systemImage: "person.circle",
            description: Text("Select a profile from the list or add a new one.")
        )
    }

    // MARK: - Actions

    private func addProfile() {
        let profile = PreferencesUserProfile(
            name: "New Profile",
            email: "",
            signingKeyID: "",
            isDefault: profiles.isEmpty
        )
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func removeSelectedProfile() {
        guard let id = selectedProfileID else { return }
        profiles.removeAll { $0.id == id }
        selectedProfileID = profiles.first?.id
    }

    private func clearOtherDefaults(except keepID: UUID) {
        for index in profiles.indices where profiles[index].id != keepID {
            profiles[index].isDefault = false
        }
    }
}

// MARK: - ProfileRow

private struct ProfileRow: View {
    let profile: PreferencesUserProfile

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name.isEmpty ? "Unnamed" : profile.name)
                        .fontWeight(profile.isDefault ? .semibold : .regular)
                    if profile.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(profile.email.isEmpty ? "No email" : profile.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    UserProfilesPreferencesTab()
        .frame(width: 540, height: 440)
}
