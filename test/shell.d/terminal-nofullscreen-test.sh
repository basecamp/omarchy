#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
file="$ROOT/default/hypr/apps/terminals.lua"
grep -q 'tag = "+terminal"' "$file" || fail "terminals still tagged"
grep -q 'fullscreen = false' "$file" || fail "terminals must refuse inherited fullscreen"
pass "terminal windows do not inherit fullscreen from the focused client"
