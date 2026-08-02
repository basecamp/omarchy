#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping bar read-only injection runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cp "$SHELL_TEST_DIR/fixtures/bar-inject-readonly/shell.qml" "$test_tmp/shell.qml"
cp "$ROOT/shell/plugins/bar/BarModel.js" "$test_tmp/BarModel.js"

output=$(timeout 15 quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "bar read-only injection runtime fixture exits cleanly"
}

if ! grep -q "RESULT pass" <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "bar property injection survives read-only targets"
fi

pass "bar property injection survives read-only targets"