// FixtureVocabulary.swift
// GroveTests
//
// Seeded randomness and the names, subjects and file paths fixtures are made of.

import Foundation

/// SplitMix64: tiny, fast and identical on every platform, unlike the system generator.
struct FixtureRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Uniform in `0..<bound`.
    mutating func int(_ bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(range.count)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(next() >> 11) / Double(1 << 53) < probability
    }

    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }

    /// Skewed towards the front, so a few authors and modules dominate like in real repositories.
    mutating func skewedIndex(_ count: Int) -> Int {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return min(count - 1, Int(Double(count) * unit * unit))
    }
}

enum FixtureVocabulary {
    static let firstNames = ["Anna", "Bram", "Chloe", "Daan", "Emma", "Finn", "Grace", "Hugo", "Iris", "Jesse",
                             "Kai", "Lotte", "Milan", "Noor", "Oscar", "Priya", "Quinn", "Ravi", "Sara", "Tom",
                             "Uma", "Victor", "Wen", "Xander", "Yara", "Zoe"]
    static let lastNames = ["de Vries", "Jansen", "Bakker", "Smith", "Nguyen", "Garcia", "Okafor", "Kowalski",
                            "Tanaka", "Müller", "Rossi", "Silva", "Chen", "Patel", "Novak", "Larsen"]
    static let verbs = ["add", "fix", "update", "remove", "refactor", "simplify", "rename", "improve", "handle",
                        "support", "migrate", "extract", "cache", "debounce", "guard", "restore"]
    static let nouns = ["player controls", "login flow", "settings screen", "playback queue", "offline sync",
                        "search results", "hub rows", "deep links", "analytics events", "image cache",
                        "download manager", "subtitle picker", "cast session", "watchlist", "profile switcher",
                        "onboarding", "error banner", "focus handling", "navigation stack", "metadata fetch",
                        "token refresh", "live tv guide", "episode list", "server discovery", "remote config"]
    static let types = ["feat", "fix", "fix", "feat", "chore", "refactor", "perf", "test", "docs", "ci"]
    static let modules = ["player", "auth", "settings", "search", "home", "library", "downloads", "cast",
                          "livetv", "profile", "onboarding", "network", "storage", "ui", "analytics", "core"]
    static let folders = ["components", "screens", "hooks", "utils", "services", "state", "styles", "__tests__"]
    static let extensions = ["tsx", "ts", "ts", "tsx", "js", "json", "swift", "kt"]
    static let branchPrefixes = ["feature", "fix", "chore", "release", "spike", "hotfix", "sam", "anna", "ravi"]

    static func author(_ index: Int) -> (name: String, email: String) {
        let first = firstNames[index % firstNames.count]
        let last = lastNames[(index * 7 + index / firstNames.count) % lastNames.count]
        let handle = "\(first).\(last)".lowercased().replacingOccurrences(of: " ", with: "")
        return ("\(first) \(last)", "\(handle)@example.com")
    }

    static func subject(_ rng: inout FixtureRandom) -> String {
        let type = rng.pick(types)
        let scope = rng.pick(modules)
        let text = "\(rng.pick(verbs)) \(rng.pick(nouns))"
        return rng.chance(0.8) ? "\(type)(\(scope)): \(text)" : "\(type): \(text)"
    }

    static func body(_ rng: inout FixtureRandom) -> String {
        guard rng.chance(0.35) else { return "" }
        return "\n\nThe \(rng.pick(nouns)) now \(rng.pick(verbs))s the \(rng.pick(nouns)) when the \(rng.pick(nouns)) changes.\n"
    }

    static func branchName(_ index: Int, _ rng: inout FixtureRandom) -> String {
        let words = rng.pick(nouns).replacingOccurrences(of: " ", with: "-")
        return "\(rng.pick(branchPrefixes))/\(1_000 + index)-\(rng.pick(verbs))-\(words)"
    }

    static func filePath(_ index: Int, _ rng: inout FixtureRandom) -> String {
        let module = modules[rng.skewedIndex(modules.count)]
        let folder = rng.pick(folders)
        let noun = rng.pick(nouns).split(separator: " ").map { $0.capitalized }.joined()
        return "src/\(module)/\(folder)/\(noun)\(index).\(rng.pick(extensions))"
    }

    /// A plausible source line; the index keeps lines distinct so diffs stay small and readable.
    static func codeLine(_ rng: inout FixtureRandom, _ index: Int) -> String {
        switch rng.int(6) {
        case 0: "  const \(rng.pick(modules))\(index) = use\(rng.pick(modules).capitalized)State();"
        case 1: "  if (!\(rng.pick(modules))Ready) { return null; }"
        case 2: "  // \(rng.pick(verbs)) the \(rng.pick(nouns)) (\(index))"
        case 3: "  \(rng.pick(verbs))\(rng.pick(modules).capitalized)(\(index), options);"
        case 4: "export function \(rng.pick(verbs))\(index)(value: number) { return value * \(rng.int(97)); }"
        default: "  await client.\(rng.pick(verbs))('/\(rng.pick(modules))/\(index)');"
        }
    }
}
