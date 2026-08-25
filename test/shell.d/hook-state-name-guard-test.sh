#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

fake_home="$work_dir/home"
mkdir -p "$fake_home/.config/omarchy/hooks" "$fake_home/.local/state/omarchy"

# --- omarchy-hook --------------------------------------------------------------

# A hook name is a label, not a path. One carrying a slash, or one that is a
# bare `.` or `..`, would run a script from outside the hooks directory.

cat >"$fake_home/.config/omarchy/hooks/test-hook" <<'SH'
touch "$HOME/hook-ran"
SH

HOME="$fake_home" "$ROOT/bin/omarchy-hook" test-hook
[[ -f $fake_home/hook-ran ]] ||
  fail "omarchy hook runs a named hook from the hooks directory"
pass "omarchy hook runs a named hook from the hooks directory"

# Dots inside a name are not a path. a..b stays inside the hooks directory.
cat >"$fake_home/.config/omarchy/hooks/a..b" <<'SH'
touch "$HOME/dotted-hook-ran"
SH

HOME="$fake_home" "$ROOT/bin/omarchy-hook" a..b
[[ -f $fake_home/dotted-hook-ran ]] ||
  fail "omarchy hook accepts a hook name with dots in the middle"
pass "omarchy hook accepts a hook name with dots in the middle"

for name in . ..; do
  status=0
  HOME="$fake_home" "$ROOT/bin/omarchy-hook" "$name" >/dev/null 2>&1 || status=$?
  (( status == 2 )) ||
    fail "omarchy hook refuses a hook name of $name" "exit: $status"
  pass "omarchy hook refuses a hook name of $name"
done

# This file sits where a name of ../../evil would resolve: hooks/../.. is
# ~/.config.
cat >"$fake_home/.config/evil" <<'SH'
touch "$HOME/escape-ran"
SH
chmod +x "$fake_home/.config/evil"

status=0
HOME="$fake_home" "$ROOT/bin/omarchy-hook" "../../evil" >/dev/null 2>&1 || status=$?
(( status == 2 )) ||
  fail "omarchy hook refuses a hook name with a dot-dot" "exit: $status"
[[ ! -e $fake_home/escape-ran ]] ||
  fail "omarchy hook runs nothing when it refuses the name"
pass "omarchy hook refuses a hook name with a dot-dot"

status=0
HOME="$fake_home" "$ROOT/bin/omarchy-hook" "sub/dir" >/dev/null 2>&1 || status=$?
(( status == 2 )) ||
  fail "omarchy hook refuses a hook name with a slash" "exit: $status"
pass "omarchy hook refuses a hook name with a slash"

# --- omarchy-state -------------------------------------------------------------

state_dir="$fake_home/.local/state/omarchy"

HOME="$fake_home" "$ROOT/bin/omarchy-state" set reboot-required
[[ -f $state_dir/reboot-required ]] ||
  fail "omarchy state set still creates a plain state file"
pass "omarchy state set still creates a plain state file"

HOME="$fake_home" "$ROOT/bin/omarchy-state" set v1..2
[[ -f $state_dir/v1..2 ]] ||
  fail "omarchy state set accepts a state name with dots in the middle"
pass "omarchy state set accepts a state name with dots in the middle"

for name in . ..; do
  status=0
  HOME="$fake_home" "$ROOT/bin/omarchy-state" set "$name" >/dev/null 2>&1 || status=$?
  (( status == 2 )) ||
    fail "omarchy state set refuses a state name of $name" "exit: $status"
  pass "omarchy state set refuses a state name of $name"
done

# state/../.. is ~/.local. The guard must fire before touch gets there.
status=0
HOME="$fake_home" "$ROOT/bin/omarchy-state" set "../../escape" >/dev/null 2>&1 || status=$?
(( status == 2 )) ||
  fail "omarchy state set refuses a state name with a dot-dot" "exit: $status"
[[ ! -e $fake_home/.local/escape ]] ||
  fail "omarchy state set creates nothing outside the state directory"
pass "omarchy state set refuses a state name with a dot-dot"

status=0
HOME="$fake_home" "$ROOT/bin/omarchy-state" set "sub/dir" >/dev/null 2>&1 || status=$?
(( status == 2 )) ||
  fail "omarchy state set refuses a state name with a slash" "exit: $status"
pass "omarchy state set refuses a state name with a slash"

# clear takes patterns by design ("state-name-or-pattern") and matches
# basenames through find -name, so it can never walk out of the directory.
touch "$state_dir/restart-a-required" "$state_dir/restart-b-required" "$state_dir/keep-me"
HOME="$fake_home" "$ROOT/bin/omarchy-state" clear "restart-*-required"
[[ ! -e $state_dir/restart-a-required && ! -e $state_dir/restart-b-required && -f $state_dir/keep-me ]] ||
  fail "omarchy state clear still clears matching patterns only"
pass "omarchy state clear still clears matching patterns only"
