#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

# The fixture prints what fprintd-list prints, format strings and all:
# " - #%d: %s" per enrolled finger, and "User %s has no fingers enrolled for
# %s." when there are none.
stub_fprintd_list() {
  cat >"$tmp_dir/bin/fprintd-list"
  chmod +x "$tmp_dir/bin/fprintd-list"
}

drop_fprintd_list() {
  rm -f "$tmp_dir/bin/fprintd-list"
}

fingerprint_enrolled() {
  PATH="$tmp_dir/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-hw-fingerprint-enrolled" "$@"
}

assert_enrolled() {
  local description="$1"

  fingerprint_enrolled alice || fail "$description"
  pass "$description"
}

assert_not_enrolled() {
  local description="$1"

  if fingerprint_enrolled alice; then
    fail "$description"
  fi
  pass "$description"
}

stub_fprintd_list <<'STUB'
#!/bin/bash
cat <<'OUT'
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
Fingerprints for user alice on Goodix MOC Fingerprint Sensor (press):
 - #0: right-index-finger
OUT
STUB
assert_enrolled "a user with an enrolled finger reads as enrolled"

# The reason this command exists: the empty-enrollment message names fingers
# too, so any match on the word alone reports the opposite of the truth.
stub_fprintd_list <<'STUB'
#!/bin/bash
cat <<'OUT'
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
User alice has no fingers enrolled for Goodix MOC Fingerprint Sensor.
OUT
STUB
assert_not_enrolled "an empty enrollment does not read as enrolled"

stub_fprintd_list <<'STUB'
#!/bin/bash
echo "found 0 devices" >&2
exit 1
STUB
assert_not_enrolled "a machine with no reader does not read as enrolled"

drop_fprintd_list
assert_not_enrolled "a machine without fprintd does not read as enrolled"
