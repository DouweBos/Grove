// Domain/CommitTemplateStore.swift
// Grove
//
// Where Grove keeps the commit message templates managed in Preferences.

import Foundation
import GroveKit

extension CommitTemplateStore {
    static let shared = CommitTemplateStore(
        load: { PlistStore.load([CommitTemplate].self, from: CommitTemplateStore.filename) },
        save: { PlistStore.save($0, to: CommitTemplateStore.filename) }
    )

    nonisolated static let filename = "CommitTemplates.plist"
}
