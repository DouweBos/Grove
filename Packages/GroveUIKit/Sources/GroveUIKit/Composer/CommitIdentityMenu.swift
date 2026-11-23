// Composer/CommitIdentityMenu.swift
// GroveUIKit
//
// Who the next commit is authored as, with a menu to switch this repository to a saved profile.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitIdentityMenu: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @State private var profiles: [UserProfile] = []
    @State private var isNaming = false
    @State private var label = ""

    var body: some View {
        Group {
            if let source = host.profiles {
                Menu { items(source) } label: { self.label(profile: profiles.first { $0.matches(viewModel.identity) }) }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .gitClickable()
                    .onAppear { profiles = source.load() }
                    .alert("Save Identity Profile", isPresented: $isNaming) {
                        TextField("Name, e.g. Work", text: $label)
                        Button("Save") {
                            if let identity = viewModel.identity { source.save?(identity, label) }
                            profiles = source.load()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Saved profiles can be picked in any repository.")
                    }
            } else {
                self.label(profile: nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .help(help)
    }

    @ViewBuilder
    private func items(_ source: GitIdentityProfiles) -> some View {
        let current = source.load()
        Section("Commit As") {
            ForEach(current) { profile in
                Button {
                    viewModel.act { await viewModel.switchIdentity(to: profile) }
                } label: {
                    Label("\(profile.title) \u{2014} \(profile.email)",
                          systemImage: profile.matches(viewModel.identity) ? "checkmark" : "person.crop.circle")
                }
            }
        }
        if let identity = viewModel.identity, source.save != nil, !current.contains(where: { $0.matches(identity) }) {
            Divider()
            Button("Save \u{201C}\(identity.email)\u{201D} as a Profile") {
                label = ""
                isNaming = true
            }
        }
        if let remove = source.remove, !current.isEmpty {
            Menu("Remove Profile") {
                ForEach(current) { profile in
                    Button(profile.title) {
                        remove(profile)
                        profiles = source.load()
                    }
                }
            }
        }
        if let manage = source.manage {
            Divider()
            Button(current.isEmpty ? "Add a Profile in Settings" : "Manage Profiles", action: manage)
        }
    }

    private func label(profile: UserProfile?) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if let identity = viewModel.identity {
                GitAvatar(name: identity.name, size: 22 * style.fontScale)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: GitMetrics.Spacing.xs) {
                        Text(identity.name)
                            .font(style.font(12, .medium))
                            .foregroundStyle(style.textPrimary)
                        if let profile, !profile.label.isEmpty {
                            Text(profile.label)
                                .font(style.font(10, .semibold))
                                .foregroundStyle(style.textSecondary)
                        }
                    }
                    Text(identity.email)
                        .font(style.font(11))
                        .foregroundStyle(style.textSecondary)
                }
                .lineLimit(1)
                .truncationMode(.middle)
            } else {
                Label("No git identity", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(style.font(12))
                    .foregroundStyle(style.warning)
            }
            if host.profiles != nil {
                Image(systemName: "chevron.up.chevron.down")
                    .font(style.font(9, .semibold))
                    .foregroundStyle(style.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var help: String {
        guard let identity = viewModel.identity else { return "Set user.name and user.email, or choose a profile" }
        return "Committing as \(identity.name) <\(identity.email)>. Click to switch this repository to another profile."
    }
}

/// A circle with a person's initial, for authors and committers.
public struct GitAvatar: View {
    @Environment(\.gitStyle) private var style
    private let name: String
    private let size: CGFloat

    public init(name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    private var initial: String { String(name.prefix(1)).uppercased() }
    // String.hashValue is seeded per launch; a scalar sum keeps each person's colour stable.
    private var colorIndex: Int { name.unicodeScalars.reduce(0) { $0 + Int($1.value) } }

    public var body: some View {
        Text(initial.isEmpty ? "?" : initial)
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(style.pillSelectedText)
            .frame(width: size, height: size)
            .background(style.lane(colorIndex), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        GitAvatar(name: "Douwe Bos")
        GitAvatar(name: "Test User", size: 28)
        GitAvatar(name: "")
    }
    .padding()
}
#endif
