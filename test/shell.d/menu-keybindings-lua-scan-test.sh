#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

# The keybindings menu learns about Lua-only binds by running the user's
# hyprland.lua under a stub `hl`. That stub has to survive whatever a config
# does at load time, or the scan hangs (one user config spun a `lua` at 100%
# CPU for 27 hours after a single SUPER+K) or aborts halfway, silently dropping
# every bind declared after the failing line.

script="$ROOT/bin/omarchy-menu-keybindings"
scan=$(awk '/lua <<.LUA.$/ { capture = 1; next } /^LUA$/ { capture = 0 } capture' "$script")
[[ -n $scan ]] || fail "keybindings menu embeds the Lua bind scan"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/hypr"
cat >"$TMPDIR/home/.config/hypr/hyprland.lua" <<'LUA'
-- Load-time reads a real config does against the compositor state.
for _, monitor in ipairs(hl.get_monitors()) do
  hl.monitor({ output = monitor.name, scale = monitor.scale })
end

local monitor = hl.get_active_monitor()
if not monitor or not monitor.scale or monitor.scale <= 0 then
  error("comparison should not raise")
end
local reserved = monitor.height - monitor.reserved.top * monitor.scale
local label = "monitor " .. monitor.name .. " " .. tostring(monitor.scale)
if #hl.get_workspaces() ~= 0 then
  error("stub collections should be empty")
end
if monitor.scale > 1 then
  error("stub comparisons should be false")
end

hl.bind("SUPER + K", hl.dsp.exec_cmd("omarchy-menu keybindings"), { description = "Keybindings menu" })
hl.bind("SUPER + code:20", hl.dsp.workspace({ name = "special" }), { description = "Lua only bind" })
LUA

start=$(date +%s)
output=$(HOME="$TMPDIR/home" DEBUG=1 timeout 10 lua - <<<"$scan" 2>&1) || fail "Lua bind scan exits cleanly on a config that iterates and compares compositor state (output: $output)"
(( $(date +%s) - start < 5 )) || fail "Lua bind scan terminates promptly"
pass "Lua bind scan survives load-time loops, comparisons, and arithmetic over stub state"

[[ $output != *"lua bind scan failed"* ]] || fail "Lua bind scan does not abort on stub comparisons ($output)"
grep -qF $'64\tKeybindings menu\tK\texec\tomarchy-menu keybindings' <<<"$output" || fail "Lua bind scan reports exec binds declared after load-time reads (got: $output)"
grep -qF $'64\tLua only bind\tcode:20\tlua\thl.dsp.workspace({ name = "special" })' <<<"$output" || fail "Lua bind scan reports Lua dispatcher binds (got: $output)"
pass "Lua bind scan reports binds declared after load-time compositor reads"

grep -q "timeout 10 lua <<'LUA'" "$script" || fail "Lua bind scan is time-boxed"
pass "Lua bind scan is time-boxed"
