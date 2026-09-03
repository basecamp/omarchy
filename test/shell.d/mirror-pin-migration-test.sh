#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786611349.sh"
[[ -f $migration ]] || fail "migration 1786611349.sh is missing"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

old_rule='hl.monitor({ output = "DP-7", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })'
new_rule='hl.monitor({ output = "DP-7", mode = "preferred", position = "0x1000", scale = 1, mirror = "eDP-1" })'

# $1 rule to start with ("" for none), $2 external attached, $3 switching mirroring back on succeeds
setup() {
  home_dir="$test_tmp/home"
  stub_bin="$test_tmp/bin"
  flag="$home_dir/.local/state/omarchy/toggles/hypr/internal-monitor-mirror.lua"

  rm -rf "$home_dir" "$stub_bin"
  mkdir -p "$stub_bin" "$home_dir/.local/state/omarchy/toggles/hypr"
  [[ -n $1 ]] && printf '%s\n' "$1" >"$flag"

  printf '#!/bin/bash\nexit %s\n' "$([[ $2 == yes ]] && echo 0 || echo 1)" >"$stub_bin/omarchy-hw-external-monitors"
  printf '#!/bin/bash\necho eDP-1\n' >"$stub_bin/omarchy-hyprland-monitor-laptop"

  # Stands in for the real command: switching off drops the rule, switching on
  # writes a pinned one, and the caller decides whether that second step works.
  cat >"$stub_bin/omarchy-hyprland-monitor-internal-mirror" <<SH
#!/bin/bash
rule="\$HOME/.local/state/omarchy/toggles/hypr/internal-monitor-mirror.lua"
printf '%s\n' "\$*" >>"$test_tmp/calls"
[[ \$1 == off ]] && { rm -f "\$rule"; exit 0; }
[[ "$3" == yes ]] || exit 1
printf '%s\n' '$new_rule' >"\$rule"
SH

  # Switching mirroring off reloads Hyprland, so a rollback has to reload too
  # or the rule and the live session disagree.
  cat >"$stub_bin/hyprctl" <<SH
#!/bin/bash
printf 'hyprctl %s\n' "\$*" >>"$test_tmp/calls"
SH

  chmod +x "$stub_bin"/*
  rm -f "$test_tmp/calls"
}

run_migration() {
  HOME="$home_dir" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

# --- the migration only speaks up when there is something to repair ---

setup "" yes yes
run_migration
[[ ! -f $flag ]] || fail "a machine that is not mirroring gains a rule"
[[ ! -f $test_tmp/calls ]] || fail "a machine that is not mirroring is left alone"
pass "a machine that is not mirroring is left alone"

setup "$new_rule" yes yes
run_migration
[[ $(cat "$flag") == "$new_rule" ]] || fail "an already-pinned rule is rewritten"
[[ ! -f $test_tmp/calls ]] || fail "an already-pinned rule is cycled anyway"
pass "an already-pinned rule is left alone, so a second run is a no-op"

# --- the repair itself ---

setup "$old_rule" yes yes
run_migration
[[ $(cat "$flag") == "$new_rule" ]] || fail "an auto-positioned rule is repinned"
grep -Fq 'off --quiet' "$test_tmp/calls" || fail "mirroring is switched off quietly"
grep -Fq 'on --quiet' "$test_tmp/calls" || fail "mirroring is switched back on quietly"
pass "an auto-positioned rule is repinned by cycling mirroring"

# The rule is only rewritten when mirroring is switched on, so the repair has to
# cycle it. The user did not ask for that, so it must not announce itself.
[[ $(grep -c -- '--quiet' "$test_tmp/calls") == "2" ]] ||
  fail "every step of the repair is quiet"
pass "the repair does not announce itself"

# --- a repair that cannot finish puts things back ---

setup "$old_rule" yes no
run_migration
[[ -f $flag ]] || fail "a failed repair leaves the machine extended"
[[ $(cat "$flag") == "$old_rule" ]] || fail "a failed repair restores the rule that was there"
pass "a repair that cannot switch mirroring back on restores the original rule"

# Switching mirroring off already removed the rule and reloaded, so the session
# is extended by the time anything can fail. Putting the file back without a
# reload would leave the rule claiming mirroring while the displays stay
# extended, which is the state the rollback exists to avoid.
grep -Fq 'hyprctl reload' "$test_tmp/calls" ||
  fail "restoring the rule reloads so the session matches it again"
pass "a restored rule is reloaded rather than left disagreeing with the session"

# Cycling needs somewhere to mirror to. Switching off and then failing to switch
# back on would drop mirroring for a user who never asked to lose it.
setup "$old_rule" no yes
run_migration
[[ $(cat "$flag") == "$old_rule" ]] || fail "an unplugged external leaves the rule alone"
[[ ! -f $test_tmp/calls ]] || fail "an unplugged external is not cycled"
pass "mirroring is not cycled with no external display attached"
