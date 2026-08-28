#!/bin/bash

# Covers omarchy-hyprland-monitor-rotate: the degrees the user types, the
# Hyprland `transform` those become, and the argument handling around them.
#
# Nothing here may rotate a real display, so hyprctl, omarchy-hyprland-monitor-rule
# and omarchy-hyprland-monitor-tidy are all replaced by stubs on PATH that record
# what they were asked to do. The layout the command reads comes from the stubbed
# `hyprctl monitors`, so no compositor is involved.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

ROTATE="$ROOT/bin/omarchy-hyprland-monitor-rotate"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
order_log="$test_tmp/order"
err_log="$test_tmp/stderr"
mkdir -p "$stub_bin"

# One shared log for every side effect, in the order it happened, so tests can
# assert *ordering* (the clearance pass has to run before the display turns)
# rather than just that something was called.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "monitors" ]]; then
  printf '%s\n' "$OMARCHY_TEST_MONITORS"
elif [[ $1 == "eval" ]]; then
  printf 'eval %s\n' "$2" >>"$OMARCHY_TEST_ORDER_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-rule" <<'SH'
#!/bin/bash
printf 'rule %s\n' "$*" >>"$OMARCHY_TEST_ORDER_LOG"
SH

cat >"$stub_bin/omarchy-hyprland-monitor-tidy" <<'SH'
#!/bin/bash
printf 'tidy %s\n' "$1" >>"$OMARCHY_TEST_ORDER_LOG"
SH

chmod +x "$stub_bin/hyprctl" "$stub_bin/omarchy-hyprland-monitor-rule" "$stub_bin/omarchy-hyprland-monitor-tidy"

assert_equal() {
  local actual="$1" expected="$2" description="$3"

  if [[ $actual == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected
actual:   $actual"
  fi
}

assert_true() {
  local condition="$1" description="$2" detail="${3:-}"

  if [[ $condition == "yes" ]]; then
    pass "$description"
  else
    fail "$description" "$detail"
  fi
}

# The confirmed-open defects get soft assertions so one failure does not hide the
# others; the file still exits non-zero if any of them is still broken.
open_defects=0

expect() {
  local condition="$1" description="$2" detail="${3:-}"

  if [[ $condition == "yes" ]]; then
    pass "$description"
  else
    [[ -n $detail ]] && printf '%s\n' "$detail" >&2
    printf 'not ok - %s\n' "$description" >&2
    open_defects=$((open_defects + 1))
  fi
}

yes_no() {
  if "$@"; then echo yes; else echo no; fi
}

# A layout of one focused display at the given transform, plus an unfocused
# neighbour so --monitor has something else to aim at.
layout() {
  local transform="${1:-0}"

  jq -cn --argjson t "$transform" '[
    {name:"DP-1",focused:true,width:1920,height:1080,scale:1,transform:$t,x:0,y:0,mirrorOf:"none"},
    {name:"DP-2",focused:false,width:1920,height:1080,scale:1,transform:0,x:1920,y:0,mirrorOf:"none"}
  ]'
}

rotate_out=""
rotate_status=0

# Every invocation runs under a timeout: an argument the command cannot make
# progress on must fail, not spin.
rotate() {
  local monitors="$1"
  shift

  : >"$order_log"
  : >"$err_log"
  rotate_status=0
  rotate_out=$(
    PATH="$stub_bin:$PATH" \
      OMARCHY_TEST_MONITORS="$monitors" \
      OMARCHY_TEST_ORDER_LOG="$order_log" \
      timeout 10 "$ROTATE" "$@" 2>"$err_log"
  ) || rotate_status=$?
}

applied_transform() {
  { grep '^eval ' "$order_log" || true; } | sed -n 's/.*transform = \([0-9]*\).*/\1/p' | tail -1
}

persisted_transform() {
  { grep '^rule ' "$order_log" || true; } | sed -n 's/.*transform=\([0-9]*\).*/\1/p' | tail -1
}

target_display() {
  { grep '^eval ' "$order_log" || true; } | sed -n 's/.*output = "\([^"]*\)".*/\1/p' | tail -1
}

no_side_effects() {
  [[ ! -s $order_log ]]
}

# --- degrees to transform -----------------------------------------------------

# The whole point of the command: users say degrees, Hyprland wants 0-3.
while read -r degrees expected; do
  rotate "$(layout 0)" "$degrees"

  assert_equal "$rotate_status" "0" "rotate $degrees succeeds"
  assert_equal "$(applied_transform)" "$expected" "rotate $degrees applies transform $expected"
  assert_equal "$(persisted_transform)" "$expected" "rotate $degrees persists transform $expected"
  # What it prints back must agree with what it did, so a caller reading the
  # output sees the rotation that is now in effect.
  assert_equal "$rotate_out" "$degrees" "rotate $degrees reports $degrees degrees"
done <<'CASES'
0 0
90 1
180 2
270 3
CASES

# The named aliases are documented in the usage text, so each has to land on the
# same transform as its degree form.
while read -r name expected; do
  rotate "$(layout 0)" "$name"

  assert_equal "$rotate_status" "0" "rotate $name succeeds"
  assert_equal "$(applied_transform)" "$expected" "rotate $name is transform $expected"
  assert_equal "$rotate_out" "$((expected * 90))" "rotate $name reports $((expected * 90)) degrees"
done <<'CASES'
normal 0
none 0
left 1
flip 2
inverted 2
upside-down 2
right 3
CASES

# Names are matched case-insensitively, so a shell alias or menu entry using
# capitals is not silently rejected.
rotate "$(layout 0)" "LEFT"
assert_equal "$rotate_status" "0" "rotate accepts a rotation name in capitals"
assert_equal "$(applied_transform)" "1" "rotate LEFT is the same as rotate left"

# --- flipped transforms 4-7 ---------------------------------------------------

# 4-7 are 0-3 mirrored. The invariant is: transform - 4 is the plain rotation,
# and the reported degrees stay the plain angle.
while read -r degrees expected; do
  rotate "$(layout 0)" "$degrees" --flipped

  assert_equal "$(applied_transform)" "$expected" "rotate $degrees --flipped is transform $expected"
  assert_equal "$(persisted_transform)" "$expected" "rotate $degrees --flipped persists transform $expected"
  assert_equal "$rotate_out" "$degrees" "rotate $degrees --flipped still reports $degrees degrees"
done <<'CASES'
0 4
90 5
180 6
270 7
CASES

# A display that is already mirrored must stay mirrored when it is merely
# rotated, otherwise a rotation silently undoes the mirroring.
while read -r current degrees expected; do
  rotate "$(layout "$current")" "$degrees"

  assert_equal "$(applied_transform)" "$expected" \
    "rotate $degrees from transform $current keeps the display mirrored (transform $expected)"
done <<'CASES'
4 90 5
5 180 6
6 270 7
7 0 4
CASES

# --no-flipped is the only way back out of the mirrored half.
while read -r current degrees expected; do
  rotate "$(layout "$current")" "$degrees" --no-flipped

  assert_equal "$(applied_transform)" "$expected" \
    "rotate $degrees --no-flipped from transform $current unmirrors to transform $expected"
done <<'CASES'
4 0 0
5 90 1
6 180 2
7 270 3
CASES

# --flipped on an already-mirrored display is a no-op rather than a double flip
# back to the plain half.
rotate "$(layout 5)" 90 --flipped
assert_equal "$(applied_transform)" "5" "rotate --flipped on an already mirrored display stays mirrored"

# An unmirrored display stays unmirrored without --flipped, and --no-flipped on
# one changes nothing about the mirroring.
rotate "$(layout 0)" 90
assert_equal "$(applied_transform)" "1" "rotate leaves an unmirrored display unmirrored"
rotate "$(layout 1)" 270 --no-flipped
assert_equal "$(applied_transform)" "3" "rotate --no-flipped on an unmirrored display just rotates"

# Asking for the rotation a display is already in must still produce that
# rotation: running the command twice is the same as running it once.
rotate "$(layout 1)" 90
first_transform=$(applied_transform)
first_out="$rotate_out"
rotate "$(layout "$first_transform")" 90
assert_equal "$(applied_transform)" "$first_transform" "rotating to the current rotation is idempotent"
assert_equal "$rotate_out" "$first_out" "rotating to the current rotation reports the same degrees"

# --- reading the current rotation ---------------------------------------------

# With no rotation the command is a read: every transform 0-7 reports its plain
# angle, and nothing is written anywhere.
for current in 0 1 2 3 4 5 6 7; do
  rotate "$(layout "$current")"

  assert_equal "$rotate_status" "0" "reading the rotation of transform $current succeeds"
  assert_equal "$rotate_out" "$(((current % 4) * 90))" "transform $current reads as $(((current % 4) * 90)) degrees"
  assert_true "$(yes_no no_side_effects)" "reading the rotation of transform $current changes nothing" \
    "side effects: $(cat "$order_log")"
done

# --- rejected rotations -------------------------------------------------------

# Only quarter turns exist as transforms. Anything else must be refused
# outright, and refused *before* anything is applied -- a half-applied rotation
# would leave the live layout and monitors.lua disagreeing.
for bad in 45 91 360 -90 1 3 89 270.0 900 leftish "90deg" "  "; do
  rotate "$(layout 0)" "$bad"

  assert_true "$(yes_no test "$rotate_status" -ne 0)" "rotate rejects '$bad'" \
    "exit=$rotate_status out=$rotate_out"
  assert_true "$(yes_no no_side_effects)" "rotate applies nothing for '$bad'" \
    "side effects: $(cat "$order_log")"
  assert_true "$(yes_no test -s "$err_log")" "rotate explains why '$bad' was rejected"
done

# An empty rotation argument is read as "no rotation given", which is at worst
# harmless: what must never happen is a partial turn, so nothing may be applied.
rotate "$(layout 2)" ""
assert_true "$(yes_no no_side_effects)" "rotate applies nothing for an empty rotation" \
  "side effects: $(cat "$order_log")"

# --- argument validation ------------------------------------------------------

# A second rotation is ambiguous, so it is an error rather than last-wins.
rotate "$(layout 0)" 90 180
assert_true "$(yes_no test "$rotate_status" -ne 0)" "rotate rejects two rotations"
assert_true "$(yes_no no_side_effects)" "rotate applies nothing when given two rotations"

# An unknown display name must not fall back to the focused one.
rotate "$(layout 0)" 90 --monitor NO-SUCH
assert_true "$(yes_no test "$rotate_status" -ne 0)" "rotate rejects an unknown display"
assert_true "$(yes_no no_side_effects)" "rotate applies nothing for an unknown display"

# Nothing to rotate is an error, not a silent success.
rotate '[]' 90
assert_true "$(yes_no test "$rotate_status" -ne 0)" "rotate fails when there is no display at all"
assert_true "$(yes_no no_side_effects)" "rotate applies nothing when there is no display"

# No display is focused (a locked or headless session): there is no sensible
# default target, so it must not pick one arbitrarily.
UNFOCUSED='[{"name":"DP-1","focused":false,"width":1920,"height":1080,"scale":1,"transform":0,"x":0,"y":0,"mirrorOf":"none"}]'
rotate "$UNFOCUSED" 90
assert_true "$(yes_no test "$rotate_status" -ne 0)" "rotate fails when no display is focused"
assert_true "$(yes_no no_side_effects)" "rotate applies nothing when no display is focused"

# --monitor aims at a named display instead of the focused one, in both spellings.
rotate "$(layout 0)" 90 --monitor DP-2
assert_equal "$rotate_status" "0" "rotate --monitor targets a named display"
assert_equal "$(target_display)" "DP-2" "rotate --monitor DP-2 rotates DP-2"
rotate "$(layout 0)" 90 --monitor=DP-2
assert_equal "$(target_display)" "DP-2" "rotate --monitor=DP-2 rotates DP-2"

# Order of flags and rotation must not matter.
rotate "$(layout 0)" --monitor DP-2 --flipped 270
assert_equal "$(applied_transform)" "7" "rotate accepts the rotation after its flags"
assert_equal "$(target_display)" "DP-2" "rotate still targets the named display with the rotation last"

# --help is a documented read-only path.
for flag in -h --help; do
  rotate "$(layout 0)" "$flag"

  assert_equal "$rotate_status" "0" "rotate $flag succeeds"
  assert_true "$(yes_no grep -q 'Usage:' <<<"$rotate_out")" "rotate $flag prints usage"
  assert_true "$(yes_no no_side_effects)" "rotate $flag changes nothing"
done

# The usage text is the only documentation of the rotation vocabulary, so it has
# to actually list the words the parser accepts.
rotate "$(layout 0)" --help
for word in 90 180 270 left right flip --flipped --no-flipped --no-tidy; do
  assert_true "$(yes_no grep -q -- "$word" <<<"$rotate_out")" "usage mentions $word"
done

# --- tidying ------------------------------------------------------------------

# A quarter turn changes the display's footprint, so by default neighbours are
# re-packed: once to clear room *before* the turn (Hyprland warns the instant two
# displays overlap) and once afterwards to close the gap that left.
rotate "$(layout 0)" 90
tidy_calls=$(grep -c '^tidy' "$order_log" || true)
assert_true "$(yes_no test "$tidy_calls" -ge 1)" "rotate re-packs displays by default"
assert_equal \
  "$(grep -n '^tidy\|^eval' "$order_log" | head -1 | cut -d: -f2 | cut -d' ' -f1)" \
  "tidy" \
  "rotate clears room before it turns the display"

# --no-tidy leaves positions alone but must still perform the rotation itself.
rotate "$(layout 0)" 90 --no-tidy
assert_equal "$rotate_status" "0" "rotate --no-tidy succeeds"
assert_equal "$(grep -c '^tidy' "$order_log" || true)" "0" "rotate --no-tidy re-packs nothing"
assert_equal "$(applied_transform)" "1" "rotate --no-tidy still applies the rotation"
assert_equal "$(persisted_transform)" "1" "rotate --no-tidy still persists the rotation"

# A rotation is only useful if it survives a reload, so the live change and the
# persisted rule must always agree.
for degrees in 0 90 180 270; do
  rotate "$(layout 0)" "$degrees" --flipped
  assert_equal "$(applied_transform)" "$(persisted_transform)" \
    "the live and persisted transform agree for $degrees --flipped"
done

# --- regressions for confirmed defects ---------------------------------------

# A value-taking flag given no value must fail, not loop forever. `shift 2` on a
# single remaining argument shifts nothing, so the parser can spin at 100% CPU.
for flag in --monitor; do
  rotate "$(layout 0)" "$flag"

  expect "$(yes_no test "$rotate_status" -ne 124)" "rotate $flag with no value terminates" \
    "timed out: the argument loop never made progress"
  expect "$(yes_no test "$rotate_status" -ne 0)" "rotate $flag with no value is an error"
done

# An explicitly empty --monitor= is a scripted caller interpolating an unset
# variable; retargeting the focused display instead is how the wrong display
# gets rotated.
rotate "$(layout 0)" 90 --monitor=
expect "$(yes_no test "$rotate_status" -ne 0)" "rotate rejects an empty --monitor=" \
  "exit=$rotate_status, rotated: $(target_display)"
expect "$(yes_no no_side_effects)" "rotate applies nothing for an empty --monitor=" \
  "side effects: $(cat "$order_log")"

# The usage text advertises --no-flipped as the way to stop mirroring. On its own
# it currently prints the current angle and exits 0 having done nothing, so the
# documented way to unmirror silently does not work.
rotate "$(layout 5)" --no-flipped
unflipped=$(applied_transform)
expect "$(yes_no test "$rotate_status" -ne 0 -o -n "$unflipped")" \
  "rotate --no-flipped alone is not a silent no-op" \
  "exit=$rotate_status, side effects: $(cat "$order_log")"
if [[ -n $unflipped ]]; then
  expect "$(yes_no test "$unflipped" -lt 4)" "rotate --no-flipped alone unmirrors the display"
fi

if ((open_defects)); then
  printf '%s confirmed defect(s) still unfixed\n' "$open_defects" >&2
  exit 1
fi
