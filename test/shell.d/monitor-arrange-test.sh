#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
fake_home=$(mktemp -d)
hyprctl_log="$fake_home/hyprctl.log"
hyprctl_result_file="$fake_home/hyprctl-result"

cleanup() {
  rm -rf "$test_bin" "$fake_home"
}
trap cleanup EXIT

# The fake hyprctl records every `eval` argument it was given and answers
# with whatever this test staged in $hyprctl_result_file, so each case can
# drive both a successful and a rejected Hyprland response.
cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
if [[ $1 == eval ]]; then
  printf '%s\n' "$2" >>"$HYPRCTL_LOG"
  cat "$HYPRCTL_RESULT_FILE"
  exit 0
fi
exit 1
EOF
chmod +x "$test_bin"/*

arrange() {
  local command="$1" payload="$2"

  printf '%s' "$payload" | HOME="$fake_home" \
    XDG_STATE_HOME="$fake_home/state" \
    OMARCHY_MONITORS_LUA="$fake_home/monitors.lua" \
    HYPRCTL_LOG="$hyprctl_log" HYPRCTL_RESULT_FILE="$hyprctl_result_file" \
    PATH="$test_bin:$PATH" \
    bash "$ROOT/bin/omarchy-monitor-arrange" "$command"
}

two_monitor_layout='[
  { "identity": "desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896", "mode": "3440x1440@59.97", "x": 0, "y": 0, "scale": 1.25, "transform": 0, "enabled": true },
  { "identity": "eDP-1", "mode": "3000x2000@59.98", "x": 626, "y": 1152, "scale": 2, "transform": 0, "enabled": true }
]'

# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------

result=$(arrange validate "$two_monitor_layout") || fail "validate accepts a well-formed layout" "$result"
[[ $(jq -c '.' <<<"$result") == "$(jq -c '.' <<<"$two_monitor_layout")" ]] ||
  fail "validate normalizes a well-formed layout unchanged" "$result"
pass "validate accepts and normalizes a well-formed two-monitor layout"

if arrange validate '{"identity": "eDP-1"}' >/dev/null 2>&1; then
  fail "validate rejects a non-array payload"
fi
pass "validate rejects a non-array payload"

if arrange validate '[{"mode": "1920x1080@60"}]' >/dev/null 2>&1; then
  fail "validate rejects an entry missing identity"
fi
pass "validate rejects an entry missing identity"

if arrange validate '[{"identity": "eDP-1", "mode": "not-a-mode"}]' >/dev/null 2>&1; then
  fail "validate rejects a malformed mode string"
fi
pass "validate rejects a malformed mode string"

if arrange validate '[{"identity": "eDP-1", "scale": 0}]' >/dev/null 2>&1; then
  fail "validate rejects a zero scale"
fi
pass "validate rejects an out-of-range scale"

if arrange validate '[{"identity": "eDP-1", "transform": 8}]' >/dev/null 2>&1; then
  fail "validate rejects an out-of-range transform"
fi
pass "validate rejects an out-of-range transform"

if arrange validate '[{"identity": "eDP-1", "enabled": false}]' >/dev/null 2>&1; then
  fail "validate rejects a layout that disables every monitor"
fi
pass "validate rejects a layout that disables every monitor"

if arrange validate '[{"identity": "dup"}, {"identity": "dup"}]' >/dev/null 2>&1; then
  fail "validate rejects duplicate identities"
fi
pass "validate rejects duplicate identities"

# ---------------------------------------------------------------------------
# apply: transient, addressed by desc:, native Lua eval (not `keyword monitor`)
# ---------------------------------------------------------------------------

echo "ok" >"$hyprctl_result_file"
: >"$hyprctl_log"
result=$(arrange apply "$two_monitor_layout") || fail "apply succeeds when hyprctl answers ok" "$result"
[[ $(jq -r '.success' <<<"$result") == "true" ]] || fail "apply reports success" "$result"

eval_arg=$(cat "$hyprctl_log")
[[ $eval_arg == *'hl.monitor('* ]] || fail "apply uses Lua eval" "$eval_arg"
[[ $eval_arg != *'keyword monitor'* ]] || fail "apply must not fall back to keyword monitor" "$eval_arg"
[[ $eval_arg == *'output = "desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896"'* ]] ||
  fail "apply addresses the external monitor by description" "$eval_arg"
[[ $eval_arg == *'output = "eDP-1"'* ]] || fail "apply addresses the laptop panel by connector name" "$eval_arg"
[[ $eval_arg == *'position = "0x0"'* ]] || fail "apply carries explicit position" "$eval_arg"
[[ $eval_arg == *'transform = 0'* ]] || fail "apply carries transform" "$eval_arg"
pass "apply issues one hyprctl eval with hl.monitor(...) calls addressed by desc:/connector name"

echo "ok" >"$hyprctl_result_file"
: >"$hyprctl_log"
disabling_layout='[
  { "identity": "eDP-1", "mode": "preferred", "x": 0, "y": 0, "scale": 1, "transform": 0, "enabled": true },
  { "identity": "DP-1", "mode": "preferred", "x": 1920, "y": 0, "scale": 1, "transform": 0, "enabled": false }
]'
result=$(arrange apply "$disabling_layout") || fail "apply succeeds with one disabled monitor" "$result"
eval_arg=$(cat "$hyprctl_log")
[[ $eval_arg == *'output = "DP-1"'*', disabled = true'* ]] ||
  fail "apply sets disabled = true via hl.monitor, not a keyword disable" "$eval_arg"
pass "apply uses the native disabled field for a turned-off monitor"

echo 'monitor not found' >"$hyprctl_result_file"
: >"$hyprctl_log"
result=$(arrange apply "$two_monitor_layout") && fail "apply reports failure when hyprctl rejects the change"
[[ $(jq -r '.success' <<<"$result") == "false" ]] || fail "apply reports success=false on hyprctl rejection" "$result"
pass "apply surfaces a non-ok hyprctl response as a failed, non-zero result"

result=$(arrange apply '[{"identity": "desc:has \" a quote", "enabled": true}]') && \
  fail "apply refuses an identity that cannot be safely embedded in the Lua eval string"
[[ $(jq -r '.success' <<<"$result") == "false" ]] || fail "apply's refusal is reported as success=false" "$result"
pass "apply refuses a description containing a quote rather than embed it unescaped"

# ---------------------------------------------------------------------------
# persist: managed-block rewrite, live untouched
# ---------------------------------------------------------------------------

: >"$hyprctl_log"
monitors_lua="$fake_home/monitors.lua"
cat >"$monitors_lua" <<'LUA'
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA

result=$(arrange persist "$two_monitor_layout") || fail "persist succeeds against a file with no managed block yet" "$result"
[[ $(jq -r '.success' <<<"$result") == "true" ]] || fail "persist reports success" "$result"
[[ -z $(cat "$hyprctl_log" 2>/dev/null) ]] || fail "persist must never call hyprctl" "$(cat "$hyprctl_log")"

grep -qF 'hl.env("GDK_SCALE"' "$monitors_lua" ||
  fail "persist leaves pre-existing content above the managed block untouched"
grep -qF -- '-- omarchy-display-panel:managed:begin' "$monitors_lua" ||
  fail "persist appends a managed block on first adoption"
grep -qF 'output = "desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896"' "$monitors_lua" ||
  fail "persist writes the arrangement into the managed block"
backup=$(compgen -G "$fake_home/monitors.lua.bak.*" | head -n1)
[[ -n $backup ]] || fail "persist backs up the previous file before rewriting"
diff -q "$backup" <(cat <<'LUA'
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
) >/dev/null || fail "persist's backup matches the pre-rewrite file exactly"
pass "persist adopts a hand-written monitors.lua by appending a managed block and backing up first"

before_second_persist=$(cat "$monitors_lua")
result=$(arrange persist "$two_monitor_layout") || fail "persist succeeds on a file that already has a managed block" "$result"
occurrences=$(grep -c -F -- '-- omarchy-display-panel:managed:begin' "$monitors_lua")
(( occurrences == 1 )) || fail "persist rewrites the existing managed block instead of appending a second one" "$occurrences"
[[ $(cat "$monitors_lua") == "$before_second_persist" ]] ||
  fail "persist is idempotent when re-applying the same layout"
pass "persist rewrites its own managed block in place on subsequent calls, without duplicating it"

single_monitor_layout='[{ "identity": "eDP-1", "mode": "preferred", "x": 0, "y": 0, "scale": 1, "transform": 3, "enabled": true }]'
result=$(arrange persist "$single_monitor_layout") || fail "persist succeeds when reducing to one monitor" "$result"
grep -qF 'LG ULTRAGEAR' "$monitors_lua" && fail "persist's managed block must fully replace, not merge with, the previous layout"
grep -qF 'transform = 3' "$monitors_lua" || fail "persist reflects the new layout's transform"
pass "persist fully replaces the managed block's contents on each call"
