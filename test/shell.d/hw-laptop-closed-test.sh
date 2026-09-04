#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw_laptop_closed="$ROOT/bin/omarchy-hw-laptop-closed"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# logind is the only lid source every laptop answers from, so each scenario pins
# its reply and checks the exit code the callers branch on.
stub_logind() {
  mock_bin="$tmpdir/$1"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/busctl" <<SH
#!/bin/bash
printf '%s\n' "$2"
SH
  chmod +x "$mock_bin/busctl"
}

lid_status() {
  local status=0

  PATH="$mock_bin:$PATH" "$hw_laptop_closed" || status=$?
  printf '%s\n' "$status"
}

stub_logind closed "b true"
status=$(lid_status)
(( status == 0 )) || fail "a lid logind calls closed is closed" "exit: $status"
pass "a lid logind calls closed is closed"

stub_logind open "b false"
status=$(lid_status)
(( status == 1 )) || fail "a lid logind calls open is open" "exit: $status"
pass "a lid logind calls open is open"

# Nothing else in the tree can stand in for logind here, so a machine whose
# logind cannot answer has to keep reaching the ACPI button this command has
# always read.
grep -F '/proc/acpi/button/lid/*/state' "$hw_laptop_closed" >/dev/null ||
  fail "the ACPI lid button stays as the fallback"
pass "the ACPI lid button stays as the fallback"
