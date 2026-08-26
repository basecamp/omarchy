#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

panel="$ROOT/shell/plugins/panels/disk-speedtest/Panel.qml"
script="$ROOT/bin/omarchy-disk-speedtest"

grep -Fq 'parts[0] === "write" || parts[0] === "stage"' "$panel" ||
  fail "disk speedtest panel treats staging samples as write-dial input"
grep -Fq 'root.phase === "write" || root.phase === "stage"' "$panel" ||
  fail "disk speedtest panel keeps the write dial live during staging"
grep -Fq 'phase = ""' "$panel" ||
  fail "disk speedtest panel starts with no phase so the read dial is not live at 0"
grep -Fq 'echo "stage ' "$script" ||
  fail "disk speedtest emits stage rates while it writes the read-test files"

pass "disk speedtest reports staging write throughput to the panel"
