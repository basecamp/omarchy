#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
flag="$home_dir/.local/state/omarchy/toggles/rotate-lock"
osd_log="$test_tmp/osd.log"

mkdir -p "$stub_bin" "$home_dir"

cat >"$stub_bin/omarchy-osd" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_OSD_LOG"
SH

cat >"$stub_bin/omarchy-hw-accelerometer" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_ACCELEROMETER:-true} == "true" ]]
SH

# The real helpers, so the flag this writes is the one the rest of Omarchy reads.
for helper in omarchy-toggle omarchy-toggle-enabled; do
  ln -s "$ROOT/bin/$helper" "$stub_bin/$helper"
done

chmod +x "$stub_bin"/omarchy-osd "$stub_bin"/omarchy-hw-accelerometer

rotate_lock() {
  HOME="$home_dir" \
    OMARCHY_TEST_OSD_LOG="$osd_log" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-toggle-rotate-lock" "$@"
}

: >"$osd_log"
rotate_lock
[[ -f $flag ]] || fail "rotate lock turns on from unset"
grep -qF -- "-m Rotate lock on" "$osd_log" ||
  fail "rotate lock announces itself" "actual:"$'\n'"$(cat "$osd_log")"
pass "rotate lock turns on from unset"

rotate_lock
[[ ! -f $flag ]] || fail "rotate lock turns back off"
grep -qF -- "-m Rotate lock off" "$osd_log" ||
  fail "rotate lock announces turning off" "actual:"$'\n'"$(cat "$osd_log")"
pass "rotate lock turns back off"

rotate_lock on
[[ -f $flag ]] || fail "rotate lock accepts an explicit on"
rotate_lock on
[[ -f $flag ]] || fail "rotate lock stays on when set on twice"
pass "rotate lock accepts an explicit on"

rotate_lock off
[[ ! -f $flag ]] || fail "rotate lock accepts an explicit off"
pass "rotate lock accepts an explicit off"

# The panel decides whether to show the row at all from this, so it has to
# answer for the hardware as well as the flag.
rotate_lock on
[[ $(rotate_lock --status) == '{"locked":true,"available":true}' ]] ||
  fail "rotate lock reports locked with a sensor present" "actual: $(rotate_lock --status)"

rotate_lock off
[[ $(OMARCHY_TEST_ACCELEROMETER=false rotate_lock --status) == '{"locked":false,"available":false}' ]] ||
  fail "rotate lock reports unavailable without a sensor" \
    "actual: $(OMARCHY_TEST_ACCELEROMETER=false rotate_lock --status)"
pass "rotate lock reports its state and whether there is a sensor to lock"

if rotate_lock sideways >/dev/null 2>&1; then
  fail "rotate lock rejects an unknown action"
fi
pass "rotate lock rejects an unknown action"
