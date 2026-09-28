#!/bin/bash
# Builds (once, cached by source hash) and runs the fixture generator. See README.md.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
sources=("$here/main.swift" "$here"/../../app/Grove/GroveTests/Fixtures/Fixture*.swift)
hash="$(cat "${sources[@]}" | shasum | cut -c1-12)"
bin_dir="${TMPDIR:-/tmp}/grove-fixtures/bin"
bin="$bin_dir/make-fixture-$hash"

if [[ ! -x "$bin" ]]; then
  mkdir -p "$bin_dir"
  echo "compiling generator..." >&2
  xcrun swiftc -O -swift-version 5 -o "$bin" "${sources[@]}"
fi

exec "$bin" "$@"
