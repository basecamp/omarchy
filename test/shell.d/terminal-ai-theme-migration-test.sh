#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1786637624.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

for command in codex grok claude pi; do
  cat >"$test_dir/bin/omarchy-theme-set-$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$AI_THEME_CALLS"
STUB
done
chmod +x "$test_dir/bin/"*

home="$test_dir/home"
calls="$test_dir/calls"
export AI_THEME_CALLS="$calls"

mkdir -p \
  "$home/.codex" \
  "$home/.grok" \
  "$home/.claude" \
  "$home/.pi/agent/extensions" \
  "$home/.local/state/omarchy/current/theme"
touch \
  "$home/.pi/agent/extensions/omarchy-system-theme.ts" \
  "$home/.local/state/omarchy/current/theme/claude.json" \
  "$home/.local/state/omarchy/current/theme/pi.json"

HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null

for command in codex grok claude pi; do
  grep -Fx "omarchy-theme-set-$command --activate" "$calls" >/dev/null ||
    fail "terminal AI migration activates $command"
done
[[ ! -e $home/.pi/agent/extensions/omarchy-system-theme.ts ]] ||
  fail "terminal AI migration removes the obsolete Pi extension"
pass "terminal AI migration activates installed supported tools"

: >"$calls"
rm -rf "$home"
mkdir -p "$home"
HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
[[ ! -s $calls ]] || fail "terminal AI migration touches unconfigured tools"
pass "terminal AI migration skips tools without existing state"
