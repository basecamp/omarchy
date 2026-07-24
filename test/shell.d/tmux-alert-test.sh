#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/tmux" <<'STUB'
#!/bin/bash

if [[ $1 == "list-windows" ]]; then
  cat "$TMUX_STUB_WINDOWS"
fi
STUB
chmod +x "$test_dir/tmux"

export TMUX_STUB_WINDOWS="$test_dir/windows"
export PATH="$test_dir:$PATH"

cat >"$TMUX_STUB_WINDOWS" <<'WINDOWS'
000|Work|1|editor
100|Work|2|claude
001|Side|1|server|with|pipes
WINDOWS

output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
expected='{"count":2,"tooltip":"claude (Work:2), server|with|pipes (Side:1)"}'
[[ $output == "$expected" ]] || fail "tmux alert reports alerted windows" "expected: $expected"$'\n'"actual:   $output"
pass "tmux alert reports alerted windows"

output=$("$ROOT/bin/omarchy-tmux-alert" show)
[[ $output == "claude (Work:2), server|with|pipes (Side:1)" ]] || fail "tmux alert describes alerted windows" "$output"
pass "tmux alert describes alerted windows"

cat >"$TMUX_STUB_WINDOWS" <<'WINDOWS'
000|Work|1|editor
WINDOWS

output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert reports no alerted windows" "$output"
pass "tmux alert reports no alerted windows"

[[ -z $("$ROOT/bin/omarchy-tmux-alert" show) ]] || fail "tmux alert stays quiet without alerts"
pass "tmux alert stays quiet without alerts"

: >"$TMUX_STUB_WINDOWS"
output=$("$ROOT/bin/omarchy-tmux-alert" show --json)
[[ $output == '{"count":0,"tooltip":""}' ]] || fail "tmux alert handles a missing tmux server" "$output"
pass "tmux alert handles a missing tmux server"
