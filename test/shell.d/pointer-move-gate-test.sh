#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const gateQml = fs.readFileSync(path.join(root, 'shell/Ui/PointerMoveGate.qml'), 'utf8')
const uiQmldir = fs.readFileSync(path.join(root, 'shell/Ui/qmldir'), 'utf8')

assert(
  /PointerMoveGate 1\.0 PointerMoveGate\.qml/.test(uiQmldir),
  'pointer movement gate is exported from qs.Ui'
)
assert(
  /property Item referenceItem: null/.test(gateQml),
  'pointer movement gate accepts a stable reference item'
)
assert(
  /property real threshold: 1/.test(gateQml),
  'pointer movement gate ignores single-pixel hover jitter'
)
assert(
  /function reset\(\)[\s\S]*root\.primed = false/.test(gateQml),
  'pointer movement gate can be disarmed after keyboard or list changes'
)
assert(
  /function reset\(\)[\s\S]*root\.initialSampleAllowed = false/.test(gateQml),
  'reset keeps the initial pointer sample ignored by default'
)
assert(
  /function allowInitialSample\(\)[\s\S]*root\.reset\(\)[\s\S]*root\.initialSampleAllowed = true/.test(gateQml),
  'pointer-initiated transitions can opt in to the initial pointer sample'
)
assert(
  /item\.mapToItem\(target, mouse\.x, mouse\.y\)/.test(gateQml),
  'pointer movement gate compares movement in stable target coordinates'
)
assert(
  /var didMove = !firstSample[\s\S]*Math\.abs\(point\.x - root\.lastX\) > root\.threshold[\s\S]*Math\.abs\(point\.y - root\.lastY\) > root\.threshold[\s\S]*root\.initialSampleAllowed/.test(gateQml),
  'pointer movement gate reports real movement or an explicitly allowed initial sample'
)
assert(
  /if \(firstSample \|\| didMove\) \{\s*root\.lastX = point\.x\s*root\.lastY = point\.y\s*\}/.test(gateQml),
  'sub-threshold pointer movement accumulates from the last accepted sample'
)
assert(
  /root\.primed = true\s*root\.initialSampleAllowed = false/.test(gateQml),
  'the initial pointer sample exception is consumed once'
)
JS

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping pointer movement gate runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cp "$SHELL_TEST_DIR/fixtures/pointer-move-gate/shell.qml" "$test_tmp/shell.qml"
ln -s "$ROOT/shell/Ui" "$test_tmp/Ui"

output=$(timeout 15 quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "pointer movement gate runtime fixture exits cleanly"
}

if ! grep -q "RESULT pass" <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "pointer movement gate runtime behavior is correct"
fi

pass "pointer movement gate runtime behavior is correct"
