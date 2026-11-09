# Fixtures and benchmarks

Fake repositories in known states, so performance work doesn't depend on real repositories and results are reproducible.

## Generate a fixture

```sh
tools/fixtures/make-fixture.sh /tmp/grove-fx/large --preset large
tools/fixtures/make-fixture.sh /tmp/grove-fx/wip --preset small --dirty 30 --stashes 3 --merge-conflict
```

The first run compiles the generator (~10 s, cached in `$TMPDIR/grove-fixtures/bin`). Output is deterministic per `--seed`
(same SHAs every time) and must be under `/tmp` or `$TMPDIR`. `--force` replaces an earlier fixture.

| preset | commits | local branches | remote branches | tags | worktrees | submodules | files | time |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `small` | 200 | 6 | 8 | 10 | 0 | 0 | 60 | ~0.2 s |
| `medium` | 2k | 50 | 80 | 200 | 2 | 1 | 600 | ~1 s |
| `large` (like a large React Native monorepo) | 10k | 30 | 700 | 5k | 7 | 3 | 3k | ~6 s |

Counts: `--commits --branches --remote-branches --tags --worktrees --submodules --files`.

States (combinable, except the two conflicts): `--dirty N` (modified, staged, staged-then-modified, untracked, deleted),
`--merge-conflict`, `--rebase-conflict`, `--detached`, `--diverged` (2 ahead, 3 behind origin), `--no-upstream`,
`--missing-worktree` (registered, folder deleted), `--stashes N`, `--large-file` (3 MB text, committed and edited),
`--binary-image` (PNG, committed and changed).

Layout: `<out>/repo` (the clone to open in Grove), `<out>/origin.git` (bare remote, so fetch/pull/push work offline),
`<out>/worktrees/*`, `<out>/submodules/*.git`. History is written with `git fast-import`: a long-lived `main` with
feature branches opened along the way, ~70% merged back (GitHub-style merge commits), the rest abandoned and stale.
Git runs with `GIT_CONFIG_GLOBAL=/dev/null` and repo-local config only.

## In tests

The generator lives in `app/Grove/GroveTests/Fixtures` (Foundation only) so tests use it directly:

```swift
let fixture = try Fixture.make(.small, states: [.mergeConflict])   // fresh temp dir
defer { fixture.remove() }
let repo = try await GitRepository(path: fixture.repo)

let shared = try Fixture.cached(FixtureSpec(.large))               // reused across runs, read-only
```

## Benchmarks

```sh
tools/fixtures/bench.sh                                  # all presets, 5 iterations
tools/fixtures/bench.sh --presets large --iterations 3
tools/fixtures/bench.sh --update-baseline                # also copies results to baseline.json
```

`GroveBenchmarks` is skipped unless `GROVE_BENCH=1`; `bench.sh` sets `TEST_RUNNER_GROVE_BENCH=1`, which xcodebuild
passes to the test process. Fixtures are cached in `$TMPDIR/grove-fixtures`, keyed by spec and generator version.
Results (median and p90 per measurement) go to `/tmp/grove-bench/results.md` and `results.json`; medians more than 20%
(and 2 ms) slower than `baseline.json` are flagged as regressions. Bump `FixtureSpec.generatorVersion` when generator
output changes.
