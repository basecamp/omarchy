#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
runtime_dir="$test_tmp/runtime"
home_dir="$test_tmp/home"
clients_json="$test_tmp/clients.json"
foot_ini="$home_dir/.config/foot/foot.ini"
mkdir -p "$mock_bin" "$runtime_dir" "$home_dir/.config/foot"
touch "$call_log"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == "clients" ]]; then
  if [[ ${HYPRCTL_DOWN:-0} == "1" ]]; then
    exit 1
  fi
  cat "$CLIENTS_JSON"
elif [[ $1 == "dispatch" ]]; then
  if [[ ${DISPATCH_FAIL:-0} == "1" ]]; then
    exit 1
  fi
fi
SH

cat >"$mock_bin/gsettings" <<'SH'
#!/bin/bash
printf 'gsettings %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == "get" && $3 == "font-name" ]]; then
  printf "'Inter Variable 11'\n"
fi
SH

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
printf 'pgrep %s\n' "$*" >>"$CALL_LOG"
if [[ ${FOOT_RUNNING:-0} == "1" ]]; then
  exit 0
else
  exit 1
fi
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'omarchy-notification-send %s\n' "$*" >>"$CALL_LOG"
printf '42\n'
SH

chmod +x "$mock_bin"/*

cat >"$clients_json" <<'JSON'
[
  {"class": "foot", "address": "0xf001"},
  {"class": "footclient", "address": "0xf002"},
  {"class": "Alacritty", "address": "0xaaaa"}
]
JSON

run_text_size() {
  CALL_LOG="$call_log" CLIENTS_JSON="$clients_json" HOME="$home_dir" \
    XDG_RUNTIME_DIR="$runtime_dir" PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-display-text-size" "$@"
}

press_count() {
  grep -Fc "address:$1\", mods = \"CTRL\", key = \"$2\"" "$call_log" || true
}

dispatch_count() {
  grep -Fc 'hyprctl dispatch' "$call_log" || true
}

notification_count() {
  grep -Fc 'omarchy-notification-send' "$call_log" || true
}

# 16px maps to a 12pt terminal font; from 9pt that is six half-point steps up.
printf 'font=monospace:size=9\n' >"$foot_ini"
run_text_size 16 >/dev/null

grep -Fq ':size=12' "$foot_ini" || fail "foot.ini is rewritten to the new point size" "$(cat "$foot_ini")"
pass "foot.ini is rewritten to the new point size"

(( $(press_count 0xf001 equal) == 6 )) || fail "the foot window is stepped up six half-points" "$(cat "$call_log")"
pass "the foot window is stepped up six half-points"

(( $(press_count 0xf002 equal) == 6 )) || fail "footclient windows are stepped too" "$(cat "$call_log")"
pass "footclient windows are stepped too"

(( $(grep -Fc 'address:0xaaaa' "$call_log" || true) == 0 )) || fail "non-foot windows are left alone" "$(cat "$call_log")"
pass "non-foot windows are left alone"

(( $(notification_count) == 0 )) || fail "no restart notification when the windows were stepped" "$(cat "$call_log")"
pass "no restart notification when the windows were stepped"

# Back down to 12px (9pt): six half-point steps with Control+minus.
run_text_size 12 >/dev/null
(( $(press_count 0xf001 minus) == 6 )) || fail "stepping down uses Control+minus" "$(cat "$call_log")"
pass "stepping down uses Control+minus"

# The same size again is a zero delta: no keypresses at all.
dispatches=$(dispatch_count)
run_text_size 12 >/dev/null
(( $(dispatch_count) == dispatches )) || fail "an unchanged size sends no keypresses" "$(cat "$call_log")"
pass "an unchanged size sends no keypresses"

# A failed dispatch falls back to the restart notification...
DISPATCH_FAIL=1 FOOT_RUNNING=1 run_text_size 16 >/dev/null
grep -Fq 'Restart Foot' "$call_log" || fail "failed dispatch falls back to the restart notification" "$(cat "$call_log")"
pass "failed dispatch falls back to the restart notification"

# ...and a second notification replaces the first instead of stacking.
DISPATCH_FAIL=1 FOOT_RUNNING=1 run_text_size 20 >/dev/null
grep -F 'omarchy-notification-send' "$call_log" | tail -1 | grep -Fq -- '-r 42' ||
  fail "repeat notifications reuse the freedesktop replaces id" "$(cat "$call_log")"
pass "repeat notifications reuse the freedesktop replaces id"

# With no compositor to ask, running foot instances still get the nudge.
printf 'font=monospace:size=9\n' >"$foot_ini"
notifications=$(notification_count)
HYPRCTL_DOWN=1 FOOT_RUNNING=1 run_text_size 16 >/dev/null
(( $(notification_count) == notifications + 1 )) || fail "no compositor still nudges running foot instances" "$(cat "$call_log")"
pass "no compositor still nudges running foot instances"

# No compositor and no foot running: nothing to notify about.
notifications=$(notification_count)
HYPRCTL_DOWN=1 run_text_size 12 >/dev/null
(( $(notification_count) == notifications )) || fail "no notification when foot is not running" "$(cat "$call_log")"
pass "no notification when foot is not running"
