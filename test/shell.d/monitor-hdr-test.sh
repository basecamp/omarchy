#!/bin/bash

# Covers omarchy-hyprland-monitor-hdr and omarchy-hyprland-monitor-capabilities.
#
# Nothing here talks to a compositor or to the user's config: hyprctl and the
# capability probe are replaced by stubs on PATH, and every rule write is
# redirected to a temp monitors.lua through OMARCHY_MONITOR_LUA. A guard below
# refuses to run at all unless the stub is the hyprctl that would be found,
# because `hdr on` issues `hyprctl eval` and that would reconfigure the real
# desktop.
#
# Assertions are collected rather than aborting on the first miss, so one
# unfixed defect does not hide the coverage below it; the run still exits
# non-zero if anything failed.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

HDR="$ROOT/bin/omarchy-hyprland-monitor-hdr"
CAPABILITIES="$ROOT/bin/omarchy-hyprland-monitor-capabilities"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STUB="$WORK/bin"
CAPS_DIR="$WORK/caps"
mkdir -p "$STUB" "$CAPS_DIR"

HYPRCTL_LOG="$WORK/hyprctl.log"
MONITORS_JSON="$WORK/monitors.json"

FAILURES=()

record_fail() {
  local description="$1" detail="${2:-}"

  FAILURES+=("$description")
  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
}

assert_equal() {
  local actual="$1" expected="$2" description="$3"

  if [[ $actual == "$expected" ]]; then
    pass "$description"
  else
    record_fail "$description" "expected: $expected
actual:   $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" description="$3"

  if [[ $haystack == *"$needle"* ]]; then
    pass "$description"
  else
    record_fail "$description" "expected to contain: $needle
actual:              $haystack"
  fi
}

# Takes a command so the reason for a failure is visible in the log.
assert_ok() {
  local description="$1"
  shift

  if "$@"; then
    pass "$description"
  else
    record_fail "$description" "failed: $*"
  fi
}

assert_nonzero_exit() {
  local status="$1" description="$2"

  if [[ $status != 0 ]]; then
    pass "$description"
  else
    record_fail "$description" "expected a non-zero exit, got 0"
  fi
}

# ---- Stubs ----

cat >"$STUB/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_HYPRCTL_LOG"

if [[ $1 == "monitors" ]]; then
  cat "$OMARCHY_TEST_MONITORS_JSON"
  exit 0
fi

# `eval` is the mutating path; the stub records it and changes nothing.
exit 0
SH

cat >"$STUB/omarchy-hyprland-monitor-capabilities" <<'SH'
#!/bin/bash
if [[ -f "$OMARCHY_TEST_CAPS_DIR/$1.json" ]]; then
  cat "$OMARCHY_TEST_CAPS_DIR/$1.json"
else
  jq -nc --arg name "$1" '{name: $name, hdr: false, reason: "no-edid"}'
fi
SH

chmod +x "$STUB"/*

export OMARCHY_TEST_HYPRCTL_LOG="$HYPRCTL_LOG"
export OMARCHY_TEST_MONITORS_JSON="$MONITORS_JSON"
export OMARCHY_TEST_CAPS_DIR="$CAPS_DIR"

# omarchy-hyprland-monitor-rule is the real one, but pointed at a temp file and
# told what the displays are so it never shells out to hyprctl itself.
export OMARCHY_MONITOR_DESCRIPTIONS='[{"name":"DP-1","description":"Acme HDR 32"},{"name":"DP-2","description":"Acme SDR 24"},{"name":"DP-3","description":"Acme Dim 27"}]'
export OMARCHY_MONITOR_SEED='{"mode":"3840x2160@144","position":"0x0","scale":"1.5"}'

TEST_PATH="$STUB:$ROOT/bin:$PATH"

# Safety guard: if the stub is not what `hyprctl` resolves to under the test
# PATH, `hdr on` would reconfigure the real session. Refuse to continue.
resolved=$(PATH="$TEST_PATH" command -v hyprctl)
[[ $resolved == "$STUB/hyprctl" ]] || fail "hyprctl stub shadows the real binary" "resolved: $resolved"
pass "hyprctl stub shadows the real binary"

# DP-1: HDR panel currently in sRGB. DP-2: SDR panel already claiming hdr as its
# preset (so "enabled" can be checked independently of capability).
cat >"$MONITORS_JSON" <<'JSON'
[
  {"name":"DP-1","focused":true,"colorManagementPreset":"srgb","currentFormat":"XRGB8888","sdrMaxLuminance":200,"sdrBrightness":1.0,"sdrSaturation":1.0},
  {"name":"DP-2","focused":false,"colorManagementPreset":"hdr","currentFormat":"XRGB2101010","sdrMaxLuminance":180,"sdrBrightness":1.0,"sdrSaturation":1.0},
  {"name":"DP-3","focused":false,"colorManagementPreset":"srgb","currentFormat":"XRGB8888","sdrMaxLuminance":100,"sdrBrightness":1.0,"sdrSaturation":1.0}
]
JSON

cat >"$CAPS_DIR/DP-1.json" <<'JSON'
{"name":"DP-1","hdr":true,"max_luminance":993,"max_avg_luminance":277,"min_luminance":0.001}
JSON
cat >"$CAPS_DIR/DP-2.json" <<'JSON'
{"name":"DP-2","hdr":false,"reason":"no-pq-eotf"}
JSON
# A panel whose advertised frame-average luminance is very low, to pin down the
# behaviour of the derived SDR white default at the bottom of its range.
cat >"$CAPS_DIR/DP-3.json" <<'JSON'
{"name":"DP-3","hdr":true,"max_luminance":400,"max_avg_luminance":50,"min_luminance":0.05}
JSON

CATCH_ALL='hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })'

reset_lua() {
  export OMARCHY_MONITOR_LUA="$WORK/monitors.lua"
  printf '%s\n' "$CATCH_ALL" >"$OMARCHY_MONITOR_LUA"
  : >"$HYPRCTL_LOG"
}

rule_get() {
  PATH="$TEST_PATH" "$ROOT/bin/omarchy-hyprland-monitor-rule" get "$1" "$2" 2>/dev/null
}

HDR_OUT="" HDR_ERR="" HDR_STATUS=0

run_hdr() {
  HDR_OUT=$(PATH="$TEST_PATH" timeout 10 "$HDR" "$@" 2>"$WORK/stderr" </dev/null)
  HDR_STATUS=$?
  HDR_ERR=$(cat "$WORK/stderr")
}

eval_count() {
  grep -c '^eval' "$HYPRCTL_LOG" 2>/dev/null || true
}

lua_unchanged() {
  [[ $(cat "$OMARCHY_MONITOR_LUA") == "$CATCH_ALL" ]]
}

is_json() {
  jq -e . >/dev/null 2>&1 <<<"$1"
}

# ---- Argument parsing ----

reset_lua
run_hdr --help
assert_equal "$HDR_STATUS" "0" "hdr --help exits 0"
assert_contains "$HDR_OUT" "Usage:" "hdr --help prints usage on stdout"
assert_equal "$(eval_count)" "0" "hdr --help asks the compositor for nothing"
assert_ok "hdr --help leaves monitors.lua alone" lua_unchanged

reset_lua
run_hdr -h
assert_equal "$HDR_STATUS" "0" "hdr -h is the same as --help"
assert_contains "$HDR_OUT" "Usage:" "hdr -h prints usage"

reset_lua
run_hdr --nonsense
assert_nonzero_exit "$HDR_STATUS" "hdr rejects an unknown flag"
assert_contains "$HDR_ERR" "Usage:" "hdr prints usage on stderr when the arguments are wrong"
assert_equal "$HDR_OUT" "" "hdr prints nothing on stdout when the arguments are wrong"
assert_ok "a rejected invocation writes no rule" lua_unchanged

reset_lua
run_hdr sideways
assert_nonzero_exit "$HDR_STATUS" "hdr rejects an unknown action"

# A flag that takes a value, given none, must fail rather than spin: run_hdr
# wraps the command in `timeout 10`, so a hang shows up as exit 124.
for flag in --monitor --sdr-brightness; do
  reset_lua
  run_hdr "$flag"
  assert_ok "hdr $flag with no value fails instead of spinning" \
    bash -c "[[ '$HDR_STATUS' != 0 && '$HDR_STATUS' != 124 ]]"
  assert_ok "hdr $flag with no value writes no rule" lua_unchanged
done

# An explicitly empty --monitor= is a caller interpolating an unset variable; it
# must not quietly retarget whichever display happens to be focused.
reset_lua
run_hdr --monitor= status
assert_nonzero_exit "$HDR_STATUS" "hdr rejects an empty --monitor="

reset_lua
run_hdr --monitor DP-9 status
assert_nonzero_exit "$HDR_STATUS" "hdr rejects an unknown display"
assert_contains "$HDR_ERR" "DP-9" "hdr names the display it could not find"
assert_ok "an unknown display writes no rule" lua_unchanged
assert_equal "$(eval_count)" "0" "an unknown display is not reconfigured"

# ---- Status output shape ----

reset_lua
run_hdr status
assert_equal "$HDR_STATUS" "0" "hdr status exits 0"
assert_ok "hdr status prints one JSON object" is_json "$HDR_OUT"
assert_equal "$(jq -r '.name' <<<"$HDR_OUT")" "DP-1" "hdr status defaults to the focused display"
assert_equal "$(jq -r '.preset' <<<"$HDR_OUT")" "srgb" "hdr status reports the live colour preset"
assert_equal "$(jq -r '.enabled' <<<"$HDR_OUT")" "false" "an sRGB display reports HDR as not enabled"
assert_equal "$(jq -r '.capable' <<<"$HDR_OUT")" "true" "hdr status reports EDID capability"
assert_equal "$(jq -r '.max_luminance' <<<"$HDR_OUT")" "993" "hdr status carries the EDID luminances through"
assert_equal "$(eval_count)" "0" "hdr status changes nothing on the compositor"
assert_ok "hdr status writes no rule" lua_unchanged

# The keys are a contract with the Display panel, which reads them by name.
for key in name enabled preset capable format sdr_max_luminance max_luminance max_avg_luminance min_luminance; do
  assert_equal "$(jq -e "has(\"$key\")" <<<"$HDR_OUT")" "true" "hdr status includes $key"
done

reset_lua
run_hdr
assert_equal "$HDR_STATUS" "0" "hdr with no arguments exits 0"
assert_ok "hdr with no arguments prints JSON" is_json "$HDR_OUT"
assert_equal "$(eval_count)" "0" "hdr with no arguments is read-only"

# enabled must track the live preset, not the EDID: DP-2 cannot do HDR but the
# compositor has it in the hdr preset anyway (e.g. it was forced).
reset_lua
run_hdr --monitor DP-2 status
assert_equal "$(jq -r '.enabled' <<<"$HDR_OUT")" "true" "enabled follows the live preset"
assert_equal "$(jq -r '.capable' <<<"$HDR_OUT")" "false" "capable follows the EDID, independently of the preset"

# ---- Refusal without EDID HDR support ----

reset_lua
run_hdr on --monitor DP-2
assert_nonzero_exit "$HDR_STATUS" "hdr on refuses a display whose EDID does not advertise HDR"
assert_contains "$HDR_ERR" "--force" "the refusal points at --force"
assert_equal "$(eval_count)" "0" "a refused hdr on reconfigures nothing"
assert_ok "a refused hdr on writes no rule" lua_unchanged

reset_lua
run_hdr on --monitor DP-2 --force
assert_equal "$HDR_STATUS" "0" "--force enables HDR on a display without EDID support"
assert_equal "$(rule_get DP-2 cm)" "hdr" "--force writes the HDR colour management rule"
assert_ok "--force issues the live reconfiguration" test "$(eval_count)" -ge 1
# The catch-all must never pick up a per-display setting (bug #6673).
assert_ok "the catch-all rule is untouched" grep -qF "$CATCH_ALL" "$OMARCHY_MONITOR_LUA"
assert_equal "$(grep -c 'output = ""' "$OMARCHY_MONITOR_LUA")" "1" "no second catch-all rule appears"

# ---- Enabling on a capable display ----

reset_lua
run_hdr on
assert_equal "$HDR_STATUS" "0" "hdr on succeeds on a capable display"
assert_ok "hdr on prints the resulting status as JSON" is_json "$HDR_OUT"
assert_equal "$(rule_get DP-1 cm)" "hdr" "hdr on persists cm = hdr"
assert_equal "$(rule_get DP-1 bitdepth)" "10" "hdr on persists 10-bit output"
assert_equal "$(rule_get DP-1 max_luminance)" "993" "hdr on persists the EDID peak luminance"
assert_equal "$(rule_get DP-1 max_avg_luminance)" "277" "hdr on persists the EDID frame-average luminance"

# SDR white is mapped below the panel's sustained full-field ceiling, or the
# whole screen visibly dims under a full white window.
sdr_default=$(rule_get DP-1 sdr_max_luminance)
assert_ok "hdr on derives an SDR white level" test -n "$sdr_default"
assert_ok "the derived SDR white is a positive whole number of nits" \
  bash -c "[[ '$sdr_default' =~ ^[0-9]+$ ]] && ((${sdr_default:-0} > 0))"
assert_ok "the derived SDR white stays under the frame-average ceiling (277)" \
  test "${sdr_default:-0}" -le 277

# Running it again must be a no-op: the panel re-enables HDR on every toggle.
before=$(cat "$OMARCHY_MONITOR_LUA")
run_hdr on
assert_equal "$HDR_STATUS" "0" "hdr on a second time still succeeds"
assert_equal "$(cat "$OMARCHY_MONITOR_LUA")" "$before" "hdr on is idempotent in monitors.lua"

# A dim panel must still get a usable SDR white rather than 0.8 of a tiny
# frame-average figure.
reset_lua
run_hdr on --monitor DP-3
assert_equal "$HDR_STATUS" "0" "hdr on succeeds on a low-luminance HDR panel"
dim_default=$(rule_get DP-3 sdr_max_luminance)
assert_ok "a dim panel still gets a legible SDR white" test "${dim_default:-0}" -ge 1
assert_ok "a dim panel's SDR white is not absurdly high" test "${dim_default:-0}" -le 1000

# Hand-tuned luminances survive enabling HDR: the script documents that it only
# fills in fields the user has not already set.
reset_lua
PATH="$TEST_PATH" "$ROOT/bin/omarchy-hyprland-monitor-rule" set DP-1 max_luminance=1234 sdr_max_luminance=111 >/dev/null
run_hdr on
assert_equal "$(rule_get DP-1 max_luminance)" "1234" "hdr on keeps a hand-tuned max_luminance"
assert_equal "$(rule_get DP-1 sdr_max_luminance)" "111" "hdr on keeps a hand-tuned SDR white"

# ---- Disabling ----

reset_lua
run_hdr on
run_hdr off
assert_equal "$HDR_STATUS" "0" "hdr off exits 0"
assert_equal "$(rule_get DP-1 cm)" "srgb" "hdr off returns the display to sRGB"
assert_equal "$(rule_get DP-1 bitdepth)" "8" "hdr off returns the display to 8-bit"
assert_equal "$(rule_get DP-1 supports_hdr)" "0" "hdr off stops advertising HDR support"
assert_equal "$(rule_get DP-1 supports_wide_color)" "0" "hdr off stops advertising wide colour"
# Documented behaviour: the tuning is kept so switching back restores it.
assert_equal "$(rule_get DP-1 max_luminance)" "993" "hdr off leaves the luminance tuning in place"

before=$(cat "$OMARCHY_MONITOR_LUA")
run_hdr off
assert_equal "$(cat "$OMARCHY_MONITOR_LUA")" "$before" "hdr off is idempotent in monitors.lua"

# ---- sdr-brightness validation ----

for bad in 0 -5 abc 12.5 " " 1e3; do
  reset_lua
  run_hdr --sdr-brightness "$bad"
  assert_nonzero_exit "$HDR_STATUS" "hdr rejects --sdr-brightness '$bad'"
  assert_ok "hdr writes no rule for --sdr-brightness '$bad'" lua_unchanged
  assert_equal "$(eval_count)" "0" "hdr reconfigures nothing for --sdr-brightness '$bad'"
done

reset_lua
run_hdr --sdr-brightness=
assert_nonzero_exit "$HDR_STATUS" "hdr rejects an empty --sdr-brightness="

reset_lua
run_hdr --sdr-brightness 250
assert_equal "$HDR_STATUS" "0" "hdr accepts a whole number of nits"
assert_equal "$(rule_get DP-1 sdr_max_luminance)" "250" "hdr persists the requested SDR white"
assert_ok "hdr applies the requested SDR white live" test "$(eval_count)" -ge 1

reset_lua
run_hdr --sdr-brightness=250
assert_equal "$HDR_STATUS" "0" "hdr accepts --sdr-brightness=NITS"
assert_equal "$(rule_get DP-1 sdr_max_luminance)" "250" "the = form persists the same value"

# An explicit value must beat the EDID-derived default in the same invocation,
# whichever order the two are computed in.
reset_lua
run_hdr on --sdr-brightness 175
assert_equal "$HDR_STATUS" "0" "hdr on with an explicit SDR white succeeds"
assert_equal "$(rule_get DP-1 sdr_max_luminance)" "175" "an explicit SDR white overrides the derived default"
assert_equal "$(rule_get DP-1 cm)" "hdr" "the on action still applies alongside --sdr-brightness"
assert_equal "$(grep -c 'sdr_max_luminance' "$OMARCHY_MONITOR_LUA")" "1" "only one SDR white value is written"

# A requested change must never be silently dropped: either apply it or refuse.
reset_lua
run_hdr status --sdr-brightness 200
if [[ $HDR_STATUS != 0 ]]; then
  pass "hdr status with --sdr-brightness is refused rather than ignored"
else
  assert_equal "$(rule_get DP-1 sdr_max_luminance)" "200" \
    "hdr status with --sdr-brightness applies the value rather than dropping it"
fi

# ---- omarchy-hyprland-monitor-capabilities ----

cap_run() {
  CAP_OUT=$(PATH="$TEST_PATH" timeout 10 "$CAPABILITIES" "$@" 2>"$WORK/stderr" </dev/null)
  CAP_STATUS=$?
  CAP_ERR=$(cat "$WORK/stderr")
}

# A connector name that cannot exist in /sys/class/drm, so the answer is
# deterministic on any machine.
ABSENT="OMARCHY-TEST-9"

: >"$HYPRCTL_LOG"
cap_run "$ABSENT"
assert_equal "$CAP_STATUS" "0" "capabilities exits 0 for a display it cannot read"
assert_ok "capabilities prints JSON" is_json "$CAP_OUT"
assert_equal "$(jq -r '.name' <<<"$CAP_OUT")" "$ABSENT" "capabilities echoes the display it was asked about"
assert_equal "$(jq -r '.hdr' <<<"$CAP_OUT")" "false" "an unreadable display is not claimed to be HDR capable"
assert_ok "capabilities gives a reason when it reports no HDR" \
  bash -c "[[ -n \$(jq -r '.reason // empty' <<<'$CAP_OUT') ]]"
assert_equal "$(jq -r 'type' <<<"$CAP_OUT")" "object" "capabilities prints a single object for a single display"

# hdr:false is only meaningful when it means "the EDID says so". Every reason it
# reports must be distinguishable, and asking about something with no EDID at
# all must not be reported as a decoded EDID lacking PQ.
assert_ok "an absent EDID is not reported as a decoded EDID without PQ" \
  bash -c "[[ \$(jq -r '.reason' <<<'$CAP_OUT') != 'no-pq-eotf' ]]"

# Real capability output is consumed by hdr, which reads .hdr and the luminance
# fields; a capable display must carry numbers, not strings.
cap_run "$ABSENT"
assert_equal "$(jq -r 'has("max_luminance") | not' <<<"$CAP_OUT")" "true" \
  "a non-capable display advertises no luminances"

# Every flag its two siblings accept is either handled or rejected. Reporting a
# flag as a non-HDR-capable display is a fabricated answer.
for flag in --help -h --bogus; do
  cap_run "$flag"
  if [[ $CAP_STATUS != 0 ]]; then
    pass "capabilities rejects $flag"
  elif [[ $flag == --bogus ]]; then
    assert_ok "capabilities $flag is not answered as if it were a display" \
      bash -c "[[ \$(jq -r '.name // empty' <<<'$CAP_OUT' 2>/dev/null) != '$flag' ]]"
  else
    # Both siblings answer -h/--help with usage text and exit 0; whatever this
    # one does, it must not invent a display called "--help".
    assert_contains "$CAP_OUT" "Usage" "capabilities $flag prints usage rather than a fabricated display"
  fi
done

# With no arguments it enumerates the compositor's displays: one JSON object per
# line, so a caller can read it with a while loop.
: >"$HYPRCTL_LOG"
cap_run
assert_equal "$CAP_STATUS" "0" "capabilities with no arguments exits 0"
assert_equal "$(printf '%s\n' "$CAP_OUT" | wc -l)" "3" "capabilities prints one line per display"
assert_ok "every enumerated line is valid JSON with a name and an hdr flag" \
  bash -c "printf '%s\n' \"\$1\" | jq -e -s 'length == 3 and all(has(\"name\") and (.hdr | type) == \"boolean\")' >/dev/null" _ "$CAP_OUT"
assert_equal "$(printf '%s\n' "$CAP_OUT" | jq -rs 'map(.name) | join(",")')" "DP-1,DP-2,DP-3" \
  "capabilities reports the displays the compositor lists, in order"

# ---- Result ----

if ((${#FAILURES[@]})); then
  fail "monitor hdr and capabilities suite" "$(printf '  %s\n' "${FAILURES[@]}")"
fi

pass "monitor hdr and capabilities suite"
