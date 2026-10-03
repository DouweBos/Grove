// ViewModels/WorkingCopyViewModel+Identity.swift
// GroveKit

import Foundation

extension WorkingCopyViewModel {

    /// Writes the profile into this repository's local config; the refresh then shows it as the identity.
    func switchIdentity(to profile: UserProfile) async {
        await mutate { try await self.repository.apply(profile) }
    }
}
