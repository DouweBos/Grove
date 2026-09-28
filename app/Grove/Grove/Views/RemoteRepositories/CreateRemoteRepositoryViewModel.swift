// Views/RemoteRepositories/CreateRemoteRepositoryViewModel.swift
// Grove

import Foundation
import Observation

/// "New Remote Repository": pick an account and owner, create, then clone it or add it as a remote.
@MainActor
@Observable
final class CreateRemoteRepositoryViewModel: Identifiable {

    enum Phase: Equatable {
        case editing
        case creating
        case created(RemoteRepository)
    }

    /// A local repository the new one can be added to as a remote.
    struct Target: Identifiable, Hashable {
        let path: String
        let name: String
        var id: String { path }
    }

    let id = UUID()
    /// Read live, so a sheet opened while the accounts still load fills in when they arrive.
    private let sectionsSource: () -> [RemoteRepositoriesViewModel.Section]
    let targets: [Target]
    private var chosenAccountID: String?
    private var chosenOwnerID: String?
    private(set) var name = ""
    private(set) var details = ""
    private(set) var isPrivate = true
    private(set) var phase: Phase = .editing
    private(set) var errorMessage: String?

    private(set) var targetPath: String?
    private(set) var remoteName = "origin"
    private(set) var isAddingRemote = false
    private(set) var addedRemote: String?
    private(set) var remoteError: String?

    /// Called with the new repository so the browser lists it.
    var onCreated: ((RemoteRepository, RemoteRepositoryOwner) async -> Void)?
    /// Runs `git remote add` in the repository at a path.
    var addRemote: ((_ path: String, _ name: String, _ url: String) async throws -> Void)?

    init(sections: @escaping () -> [RemoteRepositoriesViewModel.Section], owner: RemoteRepositoryOwner?, targets: [Target],
         preferredTarget: String?) {
        sectionsSource = sections
        self.targets = targets
        chosenAccountID = owner?.accountID
        chosenOwnerID = owner?.id
        targetPath = preferredTarget ?? targets.first?.path
    }

    // MARK: Derived

    /// Accounts that can hold a new repository: those whose owners loaded.
    var sections: [RemoteRepositoriesViewModel.Section] { sectionsSource().filter { !$0.owners.isEmpty } }
    var section: RemoteRepositoriesViewModel.Section? { sections.first { $0.id == chosenAccountID } ?? sections.first }
    var accountID: String { section?.id ?? "" }
    var owners: [RemoteRepositoryOwner] { section?.owners ?? [] }
    var owner: RemoteRepositoryOwner? { owners.first { $0.id == chosenOwnerID } ?? owners.first }
    var ownerID: String { owner?.id ?? "" }
    var supportsVisibilityAndDescription: Bool { section?.catalog.supportsVisibilityAndDescription ?? true }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Letters, digits, `.`, `-` and `_`, which every service accepts.
    var isNameValid: Bool {
        !trimmedName.isEmpty && trimmedName != "." && trimmedName != ".."
            && trimmedName.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    var canCreate: Bool { phase == .editing && owner != nil && isNameValid }

    var request: NewRemoteRepository? {
        owner.map { NewRemoteRepository(owner: $0, name: trimmedName, description: details, isPrivate: isPrivate) }
    }

    // MARK: Editing

    func selectAccount(_ id: String) {
        guard id != accountID else { return }
        chosenAccountID = id
        chosenOwnerID = nil
    }

    func selectOwner(_ id: String) { chosenOwnerID = id }
    func setName(_ text: String) { name = text; errorMessage = nil }
    func setDetails(_ text: String) { details = text }
    func setPrivate(_ value: Bool) { isPrivate = value }

    // MARK: Creating

    func create() async {
        guard canCreate, let request, let catalog = section?.catalog else { return }
        phase = .creating
        errorMessage = nil
        do {
            let created = try await catalog.createRepository(request)
            phase = .created(created)
            await onCreated?(created, request.owner)
        } catch {
            phase = .editing
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Adding as a remote

    func selectTarget(_ path: String) { targetPath = path; remoteError = nil }
    func setRemoteName(_ text: String) { remoteName = text; remoteError = nil }

    var canAddRemote: Bool {
        guard case .created = phase else { return false }
        return targetPath != nil && !remoteName.trimmingCharacters(in: .whitespaces).isEmpty && !isAddingRemote && addedRemote == nil
    }

    /// Adds the SSH URL, the one that works without a stored password.
    func addAsRemote() async {
        guard canAddRemote, case .created(let repository) = phase, let targetPath else { return }
        isAddingRemote = true
        defer { isAddingRemote = false }
        let name = remoteName.trimmingCharacters(in: .whitespaces)
        do {
            try await addRemote?(targetPath, name, repository.sshURL.isEmpty ? repository.httpsCloneURL : repository.sshURL)
            addedRemote = name
        } catch {
            remoteError = error.localizedDescription
        }
    }
}
