#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-setup-security-fingerprint"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
trap 'rm -rf "$test_tmp"' EXIT

# Pull in just the function definitions, not the top-level install/enroll
# logic below them -- that talks to pacman and a real reader, and is covered
# by manual testing instead (see the PR description). pam_fprintd_present and
# fingerprint_stack_present check fixed absolute paths (/usr/lib/security,
# the D-Bus service directory) with no override seam, so they're left to that
# same manual coverage; everything below only exercises functions whose
# dependencies are ordinary PATH commands this suite can stub.
funcs_file="$test_tmp/funcs.sh"
sed -n '1,/Setting up fingerprint scanner/p' "$setup" | sed '$d' >"$funcs_file"
source "$funcs_file"

export PATH="$stub_bin:$PATH"

### fingerprint_enrolled ###

cat >"$stub_bin/fprintd-list" <<'SH'
#!/bin/bash
[[ "${FPRINTD_LIST_MODE:-}" == "empty" ]] && exit 1
printf 'tester has 1 finger enrolled:\n #0: Right index finger\n'
SH
chmod +x "$stub_bin/fprintd-list"

FPRINTD_LIST_MODE=list fingerprint_enrolled ||
  fail "fingerprint_enrolled detects an already-enrolled finger"
pass "fingerprint_enrolled detects an already-enrolled finger"

if FPRINTD_LIST_MODE=empty fingerprint_enrolled; then
  fail "fingerprint_enrolled reports nothing enrolled when fprintd-list has nothing to say"
fi
pass "fingerprint_enrolled reports nothing enrolled when fprintd-list has nothing to say"

### enable_fingerprint_sleep_units ###

cat >"$stub_bin/systemctl" <<SH
#!/bin/bash
case "\$1" in
  list-unit-files)
    [[ ",\${SYSTEMCTL_KNOWN_UNITS:-}," == *",\$2,"* ]] || exit 1
    ;;
  is-enabled)
    [[ ",\${SYSTEMCTL_ENABLED_UNITS:-}," == *",\$3,"* ]] || exit 1
    ;;
  enable)
    printf 'enable\t%s\n' "\$2" >>"$calls"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/systemctl"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$stub_bin/sudo"

: >"$calls"
export SYSTEMCTL_KNOWN_UNITS="open-fprintd-suspend.service,open-fprintd-resume.service"
export SYSTEMCTL_ENABLED_UNITS="open-fprintd-resume.service"
enable_fingerprint_sleep_units

expected=$'enable\topen-fprintd-suspend.service'
actual=$(cat "$calls")
[[ "$actual" == "$expected" ]] ||
  fail "enable_fingerprint_sleep_units enables only a known, not-yet-enabled unit" \
    "expected: $expected$'\n'actual:   $actual"
pass "enable_fingerprint_sleep_units enables only a known, not-yet-enabled unit"

: >"$calls"
unset SYSTEMCTL_KNOWN_UNITS SYSTEMCTL_ENABLED_UNITS
enable_fingerprint_sleep_units
[[ ! -s "$calls" ]] ||
  fail "enable_fingerprint_sleep_units enables nothing when the machine has none of the units" "$(cat "$calls")"
pass "enable_fingerprint_sleep_units enables nothing when the machine has none of the units"
