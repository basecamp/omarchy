#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786439048.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
toggles="$home_dir/.local/state/omarchy/toggles/hypr"
flag="$toggles/internal-monitor-disable.lua"
overrides="$home_dir/.local/state/omarchy/display-overrides.json"

mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
[[ $1 == "monitors" ]] && printf '[{"name":"eDP-1","description":"Acme Panel SN9","x":0,"y":0}]' || exit 1
SH
chmod +x "$stub_bin"/*

run_migration() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration"
}

write_flag() {
  mkdir -p "$toggles"
  printf 'hl.monitor({ output = "eDP-1", disabled = true })\n' >"$flag"
}

reset_state() {
  rm -rf "$home_dir"
}

# --- a switched-off laptop panel is carried across ---

reset_state
write_flag
run_migration >/dev/null
[[ $(jq -r '.[] | select(.name == "eDP-1") | .disabled' "$overrides") == "true" ]] ||
  fail "the display is recorded as switched off"
[[ ! -f $flag ]] || fail "the flag file it replaces is removed"
grep -F 'disabled = true' "$home_dir/.local/state/omarchy/toggles/hypr/display-overrides.lua" >/dev/null ||
  fail "the generated rule keeps the display switched off"
pass "a switched-off laptop panel is carried into the display overrides"

# --- running twice changes nothing ---

before="$(cat "$overrides")"
run_migration >/dev/null
[[ $(cat "$overrides") == "$before" ]] || fail "a second run leaves the overrides alone"
pass "running the migration twice changes nothing"

# --- nothing to do ---

reset_state
mkdir -p "$toggles"
run_migration >/dev/null
[[ ! -f $overrides ]] || fail "a machine with no flag records nothing"
pass "a machine with nothing switched off is left alone"

# --- the old file outlives a failed write ---

# A laptop panel switched off while docked and then undocked boots to a dark
# screen, and the recovery reads both locations. Removing the old file before
# the new record exists would strand exactly that machine, so an interrupted
# run has to leave things as they were.
reset_state
write_flag
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hyprland-monitor-override"
chmod +x "$stub_bin/omarchy-hyprland-monitor-override"
run_migration >/dev/null
[[ -f $flag ]] || fail "the flag survives a record that could not be written"
rm -f "$stub_bin/omarchy-hyprland-monitor-override"
pass "the old file outlives a write that did not take"

# --- an unreadable flag is left alone rather than guessed at ---

reset_state
mkdir -p "$toggles"
printf 'something else entirely\n' >"$flag"
run_migration >/dev/null
[[ -f $flag ]] || fail "a flag with no display name in it is left in place"
[[ ! -f $overrides ]] || fail "a flag with no display name records nothing"
pass "an unreadable flag is left alone rather than guessed at"

# --- the recovery unit no longer gates on the file this removes ---

unit="$ROOT/default/systemd/user/omarchy-recover-internal-monitor.service"
! grep -F 'ConditionPathExists' "$unit" >/dev/null ||
  fail "the unit does not gate on a path this migration deletes"
grep -F 'ExecStart=/usr/bin/omarchy-hw-recover-internal-monitor' "$unit" >/dev/null ||
  fail "the unit still runs the recovery"
pass "the recovery unit no longer gates on the file this migration removes"
