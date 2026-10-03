// ViewModels/WorkingCopyViewModel+Templates.swift
// GroveKit
//
// Commit templates in the composer: the template picker, the `/` autocomplete and git's commit.template.

import Foundation

extension WorkingCopyViewModel {

    /// git's own template first, then the ones managed in Preferences.
    public var availableTemplates: [CommitTemplate] {
        [gitTemplate].compactMap { $0 } + templateStore.templates
    }

    /// Replaces the message; an empty template description keeps what was typed there.
    public func applyTemplate(_ template: CommitTemplate) {
        commitSubject = template.summary
        if !template.body.isEmpty || commitBody.isEmpty { commitBody = template.body }
        dismissAutoComplete()
    }

    /// Gitmoji go first in the summary, by convention; picking another replaces it.
    public func insertGitmoji(_ gitmoji: Gitmoji) {
        commitSubject = Gitmoji.prefixing(commitSubject, with: gitmoji)
        dismissAutoComplete()
    }

    func setGitTemplate(_ text: String?) {
        let template = text.flatMap(CommitTemplate.init(gitTemplate:))
        if template != gitTemplate { gitTemplate = template }
        prefillGitTemplateIfNeeded()
    }

    /// Like git's editor, an empty composer starts from the template; cleared by hand, it stays empty until the next commit.
    func prefillGitTemplateIfNeeded() {
        guard !didPrefillGitTemplate, let gitTemplate, !hasSubject, commitBody.isEmpty, !isAmend else { return }
        didPrefillGitTemplate = true
        applyTemplate(gitTemplate)
    }

    func templateSuggestions(query: String) -> [AutoCompleteSuggestion] {
        let matches = availableTemplates.filter {
            query.isEmpty || $0.name.lowercased().contains(query) || $0.summary.lowercased().contains(query)
        }
        return matches.map { template in
            AutoCompleteSuggestion(id: template.id.uuidString, icon: "text.badge.plus", title: template.name,
                                   subtitle: template.summary.isEmpty ? nil : template.summary, insertText: template.summary)
        }
    }

    /// A template picked from `/` also fills an empty description.
    func completeTemplate(_ suggestion: AutoCompleteSuggestion) {
        guard let template = availableTemplates.first(where: { $0.id.uuidString == suggestion.id }),
              commitBody.isEmpty, !template.body.isEmpty else { return }
        commitBody = template.body
    }
}
