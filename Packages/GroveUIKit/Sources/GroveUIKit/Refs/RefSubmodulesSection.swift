// Refs/RefSubmodulesSection.swift
// GroveUIKit

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// Submodules with their checkout state; double-click opens a cloned one where the app says.
struct SubmodulesSection: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    let context: RefContext

    var body: some View {
        let model = context.model
        let submodules = model.refs.submodules.filter { model.matches($0.path) }
        if !submodules.isEmpty {
            Section(isExpanded: Binding(get: { model.isFiltering || model.isSectionExpanded(RefSection.submodules, default: true) },
                                        set: { model.setSection(RefSection.submodules, expanded: $0) })) {
                ForEach(submodules) { row($0) }
            } header: {
                GitSectionLabel(title: "Submodules", count: submodules.count)
                    .contextMenu {
                        if let add = context.host.addSubmodule {
                            Button("Add Submodule", systemImage: "plus", action: add).requires(.submodules)
                        }
                    }
            }
        }
    }

    private func row(_ submodule: SubmoduleInfo) -> some View {
        GitSidebarRow(title: submodule.displayName, symbol: "shippingbox", tint: tint(submodule.state)) {
            switch submodule.state {
            case .upToDate: EmptyView()
            case .uninitialized: Text("not cloned").font(style.font(11, .medium))
            case .modified: Text("modified").font(style.font(11, .medium))
            case .conflicted: Text("conflict").font(style.font(11, .medium))
            }
        }
        .tag(GitRefItem.submodule(submodule.path))
        .help(tooltip(submodule))
        .contextMenu { menu(submodule) }
    }

    @ViewBuilder
    private func menu(_ submodule: SubmoduleInfo) -> some View {
        let host = context.host
        let actions = context.actions
        let isCloned = submodule.state != .uninitialized
        if let open = host.openSubmodule {
            Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { open(submodule) }.disabled(!isCloned)
        }
        if let openHere = host.openSubmoduleHere {
            Button("Open in This Window", systemImage: "arrow.up.forward.app") { openHere(submodule) }.disabled(!isCloned)
        }
        if host.openSubmodule != nil || host.openSubmoduleHere != nil { Divider() }
        if isCloned {
            Button("Update to Recorded Commit", systemImage: "arrow.down.circle") {
                Task { await actions.updateSubmodule(submodule, toRemote: false) }
            }
            .requires(.submodules)
            Button("Update to Latest Remote Commit", systemImage: "arrow.down.to.line.circle") {
                Task { await actions.updateSubmodule(submodule, toRemote: true) }
            }
            .requires(.submodules)
            Button("Fetch", systemImage: "arrow.clockwise") { Task { await actions.fetchSubmodule(submodule) } }
                .requires(.submodules)
        } else {
            Button("Initialize Submodule", systemImage: "arrow.down.circle") { Task { await actions.initSubmodule(submodule) } }
                .requires(.submodules)
        }
        Divider()
        if features.contains(.reveal) {
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([actions.repository.path.appendingPathComponent(submodule.path)])
            }
            .disabled(!isCloned)
        }
        Button("Copy Path", systemImage: "doc.on.doc") { uiHost.copy(submodule.path) }
        Divider()
        if let add = host.addSubmodule {
            Button("Add Submodule", systemImage: "plus", action: add).requires(.submodules)
        }
        Button("Remove Submodule", systemImage: "trash", role: .destructive) {
            context.model.confirmation = .removeSubmodule(submodule)
        }
        .requires(.submodules)
    }

    private func tint(_ state: SubmoduleInfo.State) -> Color {
        switch state {
        case .upToDate: style.info
        case .uninitialized: style.textSecondary
        case .modified, .conflicted: style.warning
        }
    }

    private func tooltip(_ submodule: SubmoduleInfo) -> String {
        var lines = [submodule.path]
        if let url = submodule.url { lines.append(url) }
        if let sha = submodule.shortSHA { lines.append("at \(sha)") }
        if submodule.state == .modified { lines.append("Checked out at a different commit than this repository records.") }
        if submodule.state != .uninitialized, context.host.openSubmodule != nil { lines.append("Double-click to open it") }
        return lines.joined(separator: "\n")
    }
}
#endif
