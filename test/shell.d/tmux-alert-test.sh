#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

run_node_test <<'JS'
const tmux = requireFromRoot('shell/plugins/services/tmux/TmuxModel.js')

assertEqual(tmux.waitingFromOutput('{"count":2,"tooltip":"claude (Work:2)"}').count, 2, 'tmux model reads the waiting count')
assertEqual(tmux.waitingFromOutput('{"count":2,"tooltip":"claude (Work:2)"}').tooltip, 'claude (Work:2)', 'tmux model reads the tooltip')
assertEqual(tmux.waitingFromOutput('shell noise\n{"count":1,"tooltip":"editor (Work:1)"}').count, 1, 'tmux model ignores output before the json line')
assertEqual(tmux.waitingFromOutput('').count, 0, 'tmux model treats empty output as nothing waiting')
assertEqual(tmux.waitingFromOutput('not json').count, 0, 'tmux model treats unparseable output as nothing waiting')
assertEqual(tmux.waitingFromOutput('not json').tooltip, '', 'tmux model blanks the tooltip on unparseable output')
assertEqual(tmux.waitingFromOutput('{"count":-3}').count, 0, 'tmux model clamps a negative count')
assertEqual(tmux.waitingFromOutput('{"tooltip":"editor (Work:1)"}').count, 0, 'tmux model defaults a missing count')
JS

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/tmux" <<'STUB'
#!/bin/bash

if [[ $1 == "list-windows" ]]; then
  cat "$TMUX_STUB_WINDOWS"
elif [[ $1 == "list-clients" ]]; then
  cat "$TMUX_STUB_CLIENTS"
elif [[ $1 == "set-option" ]]; then
  printf '%s\n' "$*" >>"$TMUX_STUB_CALLS"
fi
STUB
chmod +x "$test_dir/tmux"

cat >"$test_dir/omarchy-shell" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$TMUX_STUB_CALLS"
STUB
chmod +x "$test_dir/omarchy-shell"

export TMUX_STUB_WINDOWS="$test_dir/windows"
export TMUX_STUB_CLIENTS="$test_dir/clients"
export TMUX_STUB_CALLS="$test_dir/calls"
export PATH="$test_dir:$PATH"

cat >"$TMUX_STUB_WINDOWS" <<'WINDOWS'
@1:000:100::Work:1:editor
@2:100:110::Work:2:claude
@3:001:120::Side|Gig:1:server: still going
WINDOWS
: >"$TMUX_STUB_CLIENTS"

output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
expected='{"count":2,"tooltip":"claude (Work:2), server: still going (Side|Gig:1)"}'
[[ $output == "$expected" ]] || fail "tmux alert reports alerted windows" "expected: $expected"$'\n'"actual:   $output"
pass "tmux alert reports alerted windows"

output=$("$ROOT/bin/omarchy-tmux-alert" show)
[[ $output == "claude (Work:2), server: still going (Side|Gig:1)" ]] || fail "tmux alert describes alerted windows" "$output"
pass "tmux alert describes alerted windows"

cat >"$TMUX_STUB_WINDOWS" <<'WINDOWS'
@1:000:200:100:Work:1:editor
WINDOWS
echo 'attached,UTF-8:@1' >"$TMUX_STUB_CLIENTS"

output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
expected='{"count":1,"tooltip":"editor (Work:1)"}'
[[ $output == "$expected" ]] || fail "tmux alert reports output in an unfocused active window" "expected: $expected"$'\n'"actual:   $output"
pass "tmux alert reports output in an unfocused active window"

echo 'attached,focused,UTF-8:@1' >"$TMUX_STUB_CLIENTS"
output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert ignores output in a focused active window" "$output"
pass "tmux alert ignores output in a focused active window"

cat >"$TMUX_STUB_CLIENTS" <<'CLIENTS'
attached,UTF-8:@1
attached,focused,UTF-8:@1
CLIENTS
output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert ignores a window visible in another focused client" "$output"
pass "tmux alert ignores a window visible in another focused client"

echo 'attached,UTF-8:@1' >"$TMUX_STUB_CLIENTS"
cat >"$TMUX_STUB_WINDOWS" <<'WINDOWS'
@1:000:200:200:Work:1:editor
WINDOWS

output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert reports no alerted windows" "$output"
pass "tmux alert reports no alerted windows"

[[ -z $("$ROOT/bin/omarchy-tmux-alert" show) ]] || fail "tmux alert stays quiet without alerts"
pass "tmux alert stays quiet without alerts"

: >"$TMUX_STUB_WINDOWS"
: >"$TMUX_STUB_CLIENTS"
output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert handles a missing tmux server" "$output"
pass "tmux alert handles a missing tmux server"

: >"$TMUX_STUB_CALLS"
"$ROOT/bin/omarchy-tmux-alert" track @3 345
expected=$'set-option -wq -t @3 @omarchy_unfocused_activity 345\n-q omarchy.indicators refresh'
output=$(cat "$TMUX_STUB_CALLS")
[[ $output == "$expected" ]] || fail "tmux alert records the activity watermark and refreshes indicators" "expected: $expected"$'\n'"actual:   $output"
pass "tmux alert records the activity watermark and refreshes indicators"

: >"$TMUX_STUB_CALLS"
"$ROOT/bin/omarchy-tmux-alert" track invalid nope
[[ ! -s $TMUX_STUB_CALLS ]] || fail "tmux alert ignores invalid tracking arguments" "$(cat "$TMUX_STUB_CALLS")"
pass "tmux alert ignores invalid tracking arguments"
