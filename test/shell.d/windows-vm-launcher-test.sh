#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-windows-vm"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# The launcher entry is the installed-state marker: while windows-vm.desktop
# exists the menu offers Launch/Remove instead of Install. Writing it before the
# VM exists makes every cancellation path advertise a VM that was never created,
# and the install flow needs /dev/kvm and docker, so the ordering is asserted
# against the source rather than by running it.
line_of() {
  # Tolerate a missing landmark so the assertion below reports it, rather than
  # set -e killing the run with no output.
  grep -n -- "$1" "$script" 2>/dev/null | head -1 | cut -d: -f1 || true
}

writes=$(grep -c 'windows-vm\.desktop' "$script" || true)
(( writes == 2 )) ||
  fail "windows-vm.desktop is referenced exactly twice (create and remove)" "found $writes"

create_fn=$(line_of 'create_launcher_entry() {')
create_call=$(grep -n '^  create_launcher_entry$' "$script" 2>/dev/null | head -1 | cut -d: -f1 || true)
confirm=$(line_of 'gum confirm "Proceed with this configuration?"')
compose_up=$(line_of 'if ! priv up; then')

[[ -n $create_fn && -n $create_call && -n $confirm && -n $compose_up ]] ||
  fail "windows vm install still has the landmarks this test relies on"

(( create_call > confirm )) ||
  fail "the launcher entry is written after the configuration is confirmed" \
    "create at $create_call, confirm at $confirm"
(( create_call > compose_up )) ||
  fail "the launcher entry is written after the VM has started" \
    "create at $create_call, compose up at $compose_up"
pass "windows vm writes its launcher entry only after the VM starts"

# Nothing outside that function may write the marker.
create_end=$(awk -v start="$create_fn" 'NR >= start && /^}$/ { print NR; exit }' "$script")
stray=$(awk -v start="$create_fn" -v end="$create_end" \
  'NR < start || NR > end { if ($0 ~ /windows-vm\.desktop/ && $0 ~ /tee|>[^&]/) print NR": "$0 }' "$script")
[[ -z $stray ]] ||
  fail "no other path writes the launcher entry" "$stray"
pass "windows vm has a single place that creates the launcher entry"

# And the function itself still produces a usable entry.
eval "$(sed -n '/^create_launcher_entry() {/,/^}/p' "$script")"
HOME="$tmp_dir" create_launcher_entry
entry="$tmp_dir/.local/share/applications/windows-vm.desktop"
[[ -f $entry ]] || fail "create_launcher_entry writes the desktop entry"
grep -Fx 'Name=Windows' "$entry" >/dev/null || fail "the launcher entry names the app"
grep -Fx 'Exec=uwsm app -- omarchy-windows-vm launch' "$entry" >/dev/null ||
  fail "the launcher entry launches the VM"
pass "create_launcher_entry writes a usable desktop entry"
