#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/intel/video-acceleration.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'run_logged .*hardware/intel/video-acceleration.sh' "$all" ||
  fail "video acceleration is installed during hardware setup"
pass "video acceleration is installed during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

# lspci is only ever called with a device selector here, so the stub can ignore
# it and replay whatever the case under test puts in TEST_LSPCI.
cat >"$test_tmp/bin/lspci" <<'SH'
#!/bin/bash
printf '%s' "${TEST_LSPCI:-}"
SH

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$test_tmp/bin"/*

call_log="$test_tmp/calls.log"

# Sourced the way run_logged runs it.
run_leaf() {
  : >"$call_log"
  PATH="$test_tmp/bin:$PATH" \
    CALL_LOG="$call_log" \
    TEST_LSPCI="$1" \
    bash -c 'source "$1"' bash "$leaf"
}

assert_installs() {
  local description="$1" lspci_output="$2" expected="$3"

  run_leaf "$lspci_output" || fail "$description" "the leaf exited non-zero"

  local actual
  actual=$(cat "$call_log")
  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"

  pass "$description"
}

modern='pkg-add intel-media-driver libvpl vpl-gpu-rt'

# The regression this replaces: Intel dropped Iris/UHD/Arc branding for these
# parts, so a name allowlist matched none of them and installed nothing.
assert_installs "Raptor Lake reports no marketing name and still gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Intel Graphics] (rev 04)' \
  "$modern"

assert_installs "Meteor Lake gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Meteor Lake-P [Intel Graphics] (rev 08)' \
  "$modern"

assert_installs "Arrow Lake gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Arrow Lake-U [Intel Graphics]' \
  "$modern"

assert_installs "Lunar Lake gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Lunar Lake [Intel Graphics]' \
  "$modern"

assert_installs "Alder Lake-N gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-N [Intel Graphics]' \
  "$modern"

# Discrete Arc, which the old "arc" token missed because pci.ids does not
# spell out the brand for these boards.
assert_installs "discrete Battlemage gets a driver" \
  '03:00.0 VGA compatible controller: Intel Corporation Battlemage G21 [Intel Graphics]' \
  "$modern"

# The names the previous allowlist did match must keep working.
assert_installs "branded Iris Xe still gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] (rev 01)' \
  "$modern"

assert_installs "branded UHD Graphics still gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation CometLake-U GT2 [UHD Graphics] (rev 02)' \
  "$modern"

assert_installs "Panther Lake still gets a driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Panther Lake [Intel Graphics]' \
  "$modern"

# Pre-Broadwell parts predate intel-media-driver.
assert_installs "GMA falls back to the legacy driver" \
  '00:02.0 VGA compatible controller: Intel Corporation Mobile 4 Series Chipset Integrated Graphics Controller (GMA 4500MHD)' \
  'pkg-add libva-intel-driver'

assert_installs "a machine with no Intel GPU installs nothing" '' ''
