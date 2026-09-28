#!/bin/bash
# Runs the opt-in benchmark suite against generated fixtures. See README.md.
# usage: bench.sh [--presets small,medium,large] [--iterations N] [--update-baseline]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
presets="small,medium,large"
iterations=5
update_baseline=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --presets) presets="$2"; shift 2 ;;
    --iterations) iterations="$2"; shift 2 ;;
    --update-baseline) update_baseline=1; shift ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

out="/tmp/grove-bench"
rm -f "$out/results.md" "$out/results.json"
mkdir -p "$out"

# xcodebuild strips the TEST_RUNNER_ prefix and passes these to the test process.
cd "$here/../../app/Grove"
TEST_RUNNER_GROVE_BENCH=1 \
TEST_RUNNER_GROVE_BENCH_PRESETS="$presets" \
TEST_RUNNER_GROVE_BENCH_ITERATIONS="$iterations" \
TEST_RUNNER_GROVE_BENCH_OUT="$out" \
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' test -only-testing:GroveTests/GroveBenchmarks \
  > "$out/xcodebuild.log" 2>&1 || { tail -40 "$out/xcodebuild.log"; exit 1; }

if [[ ! -f "$out/results.md" ]]; then
  echo "no results written; did the suite run? see $out/xcodebuild.log" >&2
  exit 1
fi
cat "$out/results.md"
if [[ $update_baseline -eq 1 ]]; then
  cp "$out/results.json" "$here/baseline.json"
  echo "baseline updated: $here/baseline.json"
fi
