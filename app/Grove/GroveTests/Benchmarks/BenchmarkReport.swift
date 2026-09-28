// BenchmarkReport.swift
// GroveTests
//
// Times benchmark bodies, keeps median/p90 per measurement and writes results.md/json with a baseline comparison.

import Foundation

enum BenchmarkConfig {
    private static let env = ProcessInfo.processInfo.environment

    /// xcodebuild forwards `TEST_RUNNER_GROVE_BENCH=1` to the test process as `GROVE_BENCH=1`.
    static var isEnabled: Bool { env["GROVE_BENCH"] == "1" }

    static var presets: [FixturePreset] {
        let names = (env["GROVE_BENCH_PRESETS"] ?? "small,medium,large").split(separator: ",")
        return names.compactMap { FixturePreset(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }

    static var iterations: Int { Int(env["GROVE_BENCH_ITERATIONS"] ?? "") ?? 5 }

    static var outputDirectory: URL {
        URL(fileURLWithPath: env["GROVE_BENCH_OUT"] ?? "/tmp/grove-bench")
    }

    /// tools/fixtures/baseline.json in the checkout these tests were built from.
    static var baselineURL: URL {
        if let path = env["GROVE_BENCH_BASELINE"] { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/fixtures/baseline.json")
    }
}

struct BenchmarkEntry: Codable {
    let preset: String
    let name: String
    let samplesMs: [Double]
    let medianMs: Double
    let p90Ms: Double
}

struct BenchmarkResults: Codable {
    var date = ""
    var git = ""
    var iterations = 0
    var fixtures: [String: String] = [:]
    var entries: [BenchmarkEntry] = []
}

@MainActor
final class BenchmarkReport {

    static let shared = BenchmarkReport()
    /// Slower than baseline by more than this fraction (and 2 ms) counts as a regression.
    static let regressionThreshold = 0.20

    private(set) var results = BenchmarkResults()

    /// Runs `setup` untimed and `body` timed: one warm-up, then `iterations` measured runs.
    func measure<State>(_ preset: FixturePreset, _ name: String, iterations: Int = BenchmarkConfig.iterations,
                        setup: () async throws -> State, body: (State) async throws -> Void) async throws {
        var samples: [Double] = []
        for run in 0...iterations {
            let state = try await setup()
            let clock = ContinuousClock()
            let elapsed = try await clock.measure { try await body(state) }
            if run > 0 { samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000) }
        }
        let sorted = samples.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let p90 = sorted[max(0, Int((0.9 * Double(sorted.count)).rounded(.up)) - 1)]
        results.entries.removeAll { $0.preset == preset.rawValue && $0.name == name }
        results.entries.append(BenchmarkEntry(preset: preset.rawValue, name: name, samplesMs: samples, medianMs: median, p90Ms: p90))
        print("bench \(preset.rawValue) \(name): median \(format(median)) ms, p90 \(format(p90)) ms")
    }

    func noteFixture(_ preset: FixturePreset, _ label: String, _ fixture: Fixture) {
        let generated = fixture.result.seconds > 0 ? String(format: "generated in %.1fs", fixture.result.seconds) : "cached"
        results.fixtures["\(preset.rawValue) \(label)"] =
            "\(fixture.result.commits) commits, \(fixture.result.localBranches) local / \(fixture.result.remoteBranches) remote branches, "
            + "\(fixture.result.tags) tags, \(fixture.result.worktrees.count) worktrees; \(generated)"
    }

    /// Rewritten after every preset so an interrupted run still leaves results.
    func write() throws {
        results.date = ISO8601DateFormatter().string(from: Date())
        results.iterations = BenchmarkConfig.iterations
        results.git = (try? FixtureGit.run(["--version"], in: URL(fileURLWithPath: "/tmp")))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directory = BenchmarkConfig.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: directory.appendingPathComponent("results.json"))
        try Data(markdown().utf8).write(to: directory.appendingPathComponent("results.md"))
    }

    private func baseline() -> [String: BenchmarkEntry] {
        guard let data = try? Data(contentsOf: BenchmarkConfig.baselineURL),
              let decoded = try? JSONDecoder().decode(BenchmarkResults.self, from: data) else { return [:] }
        return Dictionary(decoded.entries.map { ("\($0.preset)/\($0.name)", $0) }) { first, _ in first }
    }

    private func markdown() -> String {
        let baseline = baseline()
        var lines = ["# Grove benchmarks", "", "\(results.date), \(results.git), \(results.iterations) iterations (+1 warm-up)", ""]
        lines += results.fixtures.sorted { $0.key < $1.key }.map { "- **\($0.key)**: \($0.value)" }
        lines += ["", baseline.isEmpty ? "No baseline at \(BenchmarkConfig.baselineURL.path)." : "Compared to tools/fixtures/baseline.json.", ""]
        lines += ["| preset | measurement | median ms | p90 ms | baseline ms | change |", "|---|---|---:|---:|---:|---|"]
        var regressions: [String] = []
        for entry in results.entries {
            let key = "\(entry.preset)/\(entry.name)"
            var base = "", change = ""
            if let previous = baseline[key] {
                base = format(previous.medianMs)
                let ratio = entry.medianMs / max(previous.medianMs, 0.001) - 1
                change = String(format: "%+.0f%%", ratio * 100)
                if ratio > Self.regressionThreshold && entry.medianMs - previous.medianMs > 2 {
                    change += " REGRESSION"
                    regressions.append(key)
                }
            }
            lines.append("| \(entry.preset) | \(entry.name) | \(format(entry.medianMs)) | \(format(entry.p90Ms)) | \(base) | \(change) |")
        }
        lines += ["", regressions.isEmpty ? "No regressions over 20%." : "Regressions over 20%: " + regressions.joined(separator: ", "), ""]
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double) -> String { String(format: value < 10 ? "%.2f" : "%.1f", value) }
}
