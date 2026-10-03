// Models/GitFlowTypes.swift
// GroveKit
//
// git-flow's branch model, read from and written to the same `gitflow.*` config the git-flow tools use.

import Foundation

/// The branches git-flow starts and finishes.
enum GitFlowKind: String, CaseIterable, Identifiable, Sendable {
    case feature, release, hotfix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feature: "Feature"
        case .release: "Release"
        case .hotfix: "Hotfix"
        }
    }

    var symbol: String {
        switch self {
        case .feature: "sparkles"
        case .release: "shippingbox"
        case .hotfix: "bandage"
        }
    }

    /// Releases and hotfixes are named after the version they ship.
    var namePrompt: String {
        self == .feature ? "login-screen" : "1.2.0"
    }

    /// Releases and hotfixes land on the production branch and get a tag.
    var isTagged: Bool { self != .feature }
}

struct GitFlowConfig: Equatable, Sendable {
    var productionBranch = "main"
    var developBranch = "develop"
    var featurePrefix = "feature/"
    var releasePrefix = "release/"
    var hotfixPrefix = "hotfix/"
    var versionTagPrefix = ""

    enum Key {
        static let production = "gitflow.branch.master"
        static let develop = "gitflow.branch.develop"
        static let feature = "gitflow.prefix.feature"
        static let release = "gitflow.prefix.release"
        static let hotfix = "gitflow.prefix.hotfix"
        static let versionTag = "gitflow.prefix.versiontag"
    }

    var configValues: [(key: String, value: String)] {
        [(Key.production, productionBranch), (Key.develop, developBranch), (Key.feature, featurePrefix),
         (Key.release, releasePrefix), (Key.hotfix, hotfixPrefix), (Key.versionTag, versionTagPrefix)]
    }

    /// nil unless both branch keys are set, which is what git-flow checks for "initialized".
    init?(configValues values: [String: String]) {
        guard let production = values[Key.production], let develop = values[Key.develop] else { return nil }
        productionBranch = production
        developBranch = develop
        featurePrefix = values[Key.feature] ?? featurePrefix
        releasePrefix = values[Key.release] ?? releasePrefix
        hotfixPrefix = values[Key.hotfix] ?? hotfixPrefix
        versionTagPrefix = values[Key.versionTag] ?? ""
    }

    init() {}

    func prefix(for kind: GitFlowKind) -> String {
        switch kind {
        case .feature: featurePrefix
        case .release: releasePrefix
        case .hotfix: hotfixPrefix
        }
    }

    /// Features and releases branch off develop, hotfixes off production.
    func base(for kind: GitFlowKind) -> String {
        kind == .hotfix ? productionBranch : developBranch
    }

    func branchName(_ kind: GitFlowKind, _ name: String) -> String { prefix(for: kind) + name }

    /// The kind and short name of a flow branch, e.g. `feature/login` → (.feature, "login").
    func classify(branch: String) -> (kind: GitFlowKind, name: String)? {
        for kind in GitFlowKind.allCases {
            let prefix = prefix(for: kind)
            if !prefix.isEmpty, branch.hasPrefix(prefix), branch.count > prefix.count {
                return (kind, String(branch.dropFirst(prefix.count)))
            }
        }
        return nil
    }
}

struct GitFlowFinishOptions: Equatable, Sendable {
    var keepBranch = false
    /// Features only: one commit on develop instead of a merge commit.
    var squash = false
    /// Releases and hotfixes: the annotated tag's message; nil skips tagging.
    var tagMessage: String?
    /// Push production, develop and tags to `origin` afterwards.
    var push = false
}
