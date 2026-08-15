#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-cs4208-audio.sh"
all="$ROOT/install/hardware/all.sh"
other_packages="$ROOT/install/omarchy-other.packages"
migration="$ROOT/migrations/1786719479.sh"

grep -q 'apple/fix-cs4208-audio.sh' "$all" ||
  fail "the CS4208 audio fix runs during hardware setup"
grep -qx 'macbook12-audio-driver-dkms' "$other_packages" ||
  fail "the ISO caches the CS4208 speaker driver"
grep -Fq 'MacBook9,1' "$leaf" && grep -Fq 'MacBook10,1' "$leaf" ||
  fail "the CS4208 leaf matches the 12-inch MacBooks"
pass "the CS4208 audio fix is wired into setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash

(( ${CS4208_PKG_PRESENT:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/dkms" <<'SH'
#!/bin/bash

if (( ${CS4208_DKMS_INSTALLED:-0} == 1 )); then
  echo 'macbook12-audio/0.1, 7.1.8-arch1-3, x86_64: installed (Original modules exist)'
  exit 0
fi
echo 'macbook12-spi-driver/0+git.315: added'
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local model="$1"
  : >"$calls"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_MACBOOK12_AUDIO_MODEL="$model" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf"
}

run_leaf "MacBook10,1" >/dev/null
grep -Fq $'omarchy-pkg-add\tmacbook12-audio-driver-dkms' "$calls" ||
  fail "a 2017 12-inch MacBook gets the CS4208 driver" "$(cat "$calls")"
pass "a 2017 12-inch MacBook gets the CS4208 driver"

run_leaf "MacBook9,1" >/dev/null
grep -Fq $'omarchy-pkg-add\tmacbook12-audio-driver-dkms' "$calls" ||
  fail "a 2016 12-inch MacBook gets the CS4208 driver" "$(cat "$calls")"
pass "a 2016 12-inch MacBook gets the CS4208 driver"

run_leaf "MacBook8,1" >/dev/null
[[ ! -s $calls ]] || fail "the 2015 12-inch MacBook is left alone" "$(cat "$calls")"
pass "the 2015 12-inch MacBook is left alone"

run_leaf "MacBookPro14,1" >/dev/null
[[ ! -s $calls ]] || fail "a MacBook Pro is left alone" "$(cat "$calls")"
pass "a MacBook Pro is left alone"

run_leaf "XPS 13 9310" >/dev/null
[[ ! -s $calls ]] || fail "non-Apple hardware is left alone" "$(cat "$calls")"
pass "non-Apple hardware is left alone"

run_migration() {
  : >"$calls"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_MACBOOK12_AUDIO_MODEL="$1" \
    CS4208_PKG_PRESENT="${2:-0}" \
    CS4208_DKMS_INSTALLED="${3:-0}" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration "MacBook10,1" 0 0
grep -Fq $'omarchy-pkg-add\tmacbook12-audio-driver-dkms' "$calls" ||
  fail "the migration installs the CS4208 driver" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that loads the module" "$(cat "$calls")"
pass "the migration installs the CS4208 driver"

run_migration "MacBook10,1" 1 0
[[ ! -s $calls ]] || fail "the migration skips a machine that already has the package" "$(cat "$calls")"
pass "the migration skips a machine that already has the package"

run_migration "MacBook10,1" 0 1
[[ ! -s $calls ]] || fail "the migration skips a hand-installed DKMS driver" "$(cat "$calls")"
pass "the migration skips a hand-installed DKMS driver"

run_migration "MacBookPro14,1" 0 0
[[ ! -s $calls ]] || fail "the migration skips unrelated hardware" "$(cat "$calls")"
pass "the migration skips unrelated hardware"
