#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

laptop_closed="$ROOT/bin/omarchy-hw-laptop-closed"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

lid_path="$tmpdir/lid"

# logind's LidClosed is the contract whenever logind is available, because it
# reads the lid switch through evdev while raw ACPI can report stale state.
# Each scenario pins what busctl reports and records the resulting exit.
setup_busctl() {
  mock_bin="$tmpdir/$1/bin"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/busctl" <<SH
#!/bin/bash
$2
SH
  chmod +x "$mock_bin/busctl"
}

write_lid_state() {
  rm -rf "$lid_path"
  mkdir -p "$lid_path/LID0"
  printf 'state:      %s\n' "$1" >"$lid_path/LID0/state"
}

run_laptop_closed() {
  if OMARCHY_ACPI_LID_PATH="$lid_path" PATH="$mock_bin:$PATH" "$laptop_closed"; then
    result=0
  else
    result=$?
  fi
}

setup_busctl closed 'echo "b true"'
write_lid_state open
run_laptop_closed

(( result == 0 )) ||
  fail "a lid logind reports closed is closed" "exit: $result"
pass "a lid logind reports closed is closed"

# The stale-ACPI case this exists for: firmware says closed, logind knows
# better from evdev.
setup_busctl open 'echo "b false"'
write_lid_state closed
run_laptop_closed

(( result == 1 )) ||
  fail "a lid logind reports open is open despite stale ACPI" "exit: $result"
pass "a lid logind reports open is open despite stale ACPI"

# Without a running logind, as in an install chroot, busctl produces nothing
# and the ACPI fallback decides.
setup_busctl absent 'exit 1'
write_lid_state closed
run_laptop_closed

(( result == 0 )) ||
  fail "without logind a closed ACPI lid is closed" "exit: $result"
pass "without logind a closed ACPI lid is closed"

write_lid_state open
run_laptop_closed

(( result == 1 )) ||
  fail "without logind an open ACPI lid is open" "exit: $result"
pass "without logind an open ACPI lid is open"

rm -rf "$lid_path"
run_laptop_closed

(( result == 1 )) ||
  fail "no lid device at all means open" "exit: $result"
pass "no lid device at all means open"
