#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

state_file="$test_tmp/.local/state/omarchy/idle-inhibitors"

# The idle-inhibit daemon writes its state as JSON with a count and a detail list.
# omarchy-debug-idle reads that file and renders the D-Bus inhibitors section.
run_debug_idle() {
  HOME="$test_tmp" "$ROOT/bin/omarchy-debug-idle" 2>/dev/null \
    | sed -n '/^== D-Bus idle inhibitors ==$/,/^== .* ==$/p'
}

# No state file yet: the section reports "none".
[[ ! -f $state_file ]] || fail "no state file should exist yet"
output="$(run_debug_idle)"
[[ $output == *"none"* ]] || fail "missing state file reports none" "$output"
pass "missing state file reports none"

# Empty inhibitor list: still "none".
mkdir -p "$(dirname "$state_file")"
printf '%s' '{"count":0,"inhibitors":[]}' > "$state_file"
output="$(run_debug_idle)"
[[ $output == *"none"* ]] || fail "empty inhibitor list reports none" "$output"
pass "empty inhibitor list reports none"

# Active inhibitors: section shows the count and each app/reason.
printf '%s' '{"count":2,"inhibitors":[{"app":"Zen Browser","reason":"Playing video","cookie":1},{"app":"VLC","reason":"Playing audio","cookie":2}]}' > "$state_file"
output="$(run_debug_idle)"
[[ $output == *"active count: 2"* ]] || fail "active count is shown" "$output"
[[ $output == *"Zen Browser: Playing video (cookie 1)"* ]] || fail "first inhibitor is rendered" "$output"
[[ $output == *"VLC: Playing audio (cookie 2)"* ]] || fail "second inhibitor is rendered" "$output"
pass "active inhibitors are rendered with app, reason, and cookie"

# The daemon binary is syntactically valid and declares its command metadata.
python3 -c "import ast; ast.parse(open('$ROOT/bin/omarchy-idle-inhibit').read())" \
  || fail "idle-inhibit daemon is valid python"
grep -q "omarchy:summary=" "$ROOT/bin/omarchy-idle-inhibit" \
  || fail "idle-inhibit daemon declares a summary"
grep -q "omarchy:hidden=true" "$ROOT/bin/omarchy-idle-inhibit" \
  || fail "idle-inhibit daemon is hidden from listings"
pass "idle-inhibit daemon is valid and declares its metadata"
