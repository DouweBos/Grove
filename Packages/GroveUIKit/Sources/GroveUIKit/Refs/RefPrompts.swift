// Refs/RefPrompts.swift
// GroveUIKit
//
// Confirmations the refs sidebar asks for, outside its List: a List hands a section's modifiers to every row,
// and each copy would present again.

#if os(macOS)
import GroveKit
import SwiftUI

private struct RefPrompts: ViewModifier {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    @Bindable var model: GitRefsModel
    let context: RefContext

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                model.confirmation.map(Self.title) ?? "",
                isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
                presenting: model.confirmation
            ) { confirmation in
                Button(Self.action(confirmation), role: .destructive) { Task { await model.confirm(confirmation) } }
            } message: { confirmation in
                Text(Self.message(confirmation))
            }
            .confirmationDialog(
                "Uncommitted changes",
                isPresented: Binding(get: { model.blockedCheckout != nil }, set: { if !$0 { model.blockedCheckout = nil } }),
                presenting: model.blockedCheckout
            ) { name in
                Button("Stash and Switch") { Task { await model.checkout(name, carrying: .stash) } }
                Button("Discard and Switch", role: .destructive) { Task { await model.checkout(name, carrying: .discard) } }
            } message: { name in
                Text("Your changes would be overwritten by checking out \(name). Stash them and bring them along, or discard "
                     + "changes to tracked files for good?")
            }
            .sheet(item: Binding(get: { model.pendingDrop }, set: { if $0 == nil { model.cancelDrop() } })) { drop in
                RefDropSheet(model: model, action: drop)
                    .gitUIStyle(style)
                    .gitFeatures(features)
                    .gitUIHost(uiHost)
            }
    }

    private static func title(_ confirmation: RefConfirmation) -> String {
        switch confirmation {
        case .removeRemote(let remote): "Remove remote \u{201C}\(remote.name)\u{201D}?"
        case .deleteRemoteBranch(let branch): "Delete \u{201C}\(branch.name)\u{201D} on the remote?"
        case .deleteTag(let tag): "Delete the tag \u{201C}\(tag.name)\u{201D}?"
        case .removeSubmodule(let submodule): "Remove submodule \u{201C}\(submodule.displayName)\u{201D}?"
        }
    }

    private static func action(_ confirmation: RefConfirmation) -> String {
        switch confirmation {
        case .removeRemote: "Remove Remote"
        case .deleteRemoteBranch: "Delete on Remote"
        case .deleteTag: "Delete Tag"
        case .removeSubmodule: "Remove Submodule"
        }
    }

    private static func message(_ confirmation: RefConfirmation) -> String {
        switch confirmation {
        case .removeRemote(let remote):
            "This repository forgets \(remote.url) and its remote branches. Nothing on the server changes."
        case .deleteRemoteBranch:
            "The branch is removed from the server for everyone. This can't be undone here."
        case .deleteTag:
            "Only the local tag is deleted; a pushed copy stays on the remote."
        case .removeSubmodule(let submodule):
            "Deletes \(submodule.path) and its clone, and stages the removal from .gitmodules. Uncommitted work in it is lost."
        }
    }
}

extension View {
    func refPrompts(_ model: GitRefsModel, context: RefContext) -> some View {
        modifier(RefPrompts(model: model, context: context))
    }
}
#endif
