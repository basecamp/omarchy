#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/user/hardware/apple/fix-bluetooth-codec.sh"
fragment="$ROOT/default/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf"
all="$ROOT/install/user/all.sh"
migration="$ROOT/migrations/1787263050.sh"

grep -q 'apple/fix-bluetooth-codec.sh' "$all" ||
  fail "the codec cap runs during user setup"
pass "the codec cap runs during user setup"

grep -q 'bluez5.codecs' "$fragment" || fail "the fragment sets bluez5.codecs"
grep -q '\baac\b' "$fragment" ||
  fail "the fragment keeps AAC so working devices like AirPods are not downgraded"
pass "the shipped fragment keeps AAC ahead of SBC"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
if [[ -n ${WIFI_ID:-} ]]; then
  echo "03:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/omarchy-restart-audio" <<'SH'
#!/bin/bash

printf 'omarchy-restart-audio\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

conf() { printf '%s/.config/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf' "$1"; }

run_leaf() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}"
  local home="$test_tmp/home"
  rm -rf "$home"
  mkdir -p "$home"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  local script="$test_tmp/leaf.sh"
  sed "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" "$leaf" >"$script"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" HOME="$home" \
    OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null

  printf '%s' "$home"
}

home=$(run_leaf "Apple Inc." 4488 1)
diff -q "$(conf "$home")" "$fragment" >/dev/null 2>&1 ||
  fail "a T2 Mac gets the codec cap" "$(ls -R "$home" 2>&1)"
pass "a T2 Mac gets the codec cap"

home=$(run_leaf "Apple Inc." 43ba 0)
[[ -f $(conf "$home") ]] || fail "a Mac without a T2 gets the codec cap"
pass "a Mac without a T2 gets the codec cap"

home=$(run_leaf "Apple Inc." 43a0 0)
[[ -f $(conf "$home") ]] || fail "a BCM4360 Mac gets the codec cap"
pass "a BCM4360 Mac gets the codec cap"

home=$(run_leaf "Apple Inc." 4331 0)
[[ -f $(conf "$home") ]] || fail "a BCM4331 Mac gets the codec cap"
pass "a BCM4331 Mac gets the codec cap"

# Apple Silicon Macs run Bluetooth on a newer chip generation this fix isn't
# about, so their Wi-Fi IDs are deliberately absent from the match list.
home=$(run_leaf "Apple Inc." 4425 0)
[[ ! -f $(conf "$home") ]] || fail "an Apple Silicon Mac is left alone; its Bluetooth chip is a different generation"
pass "an Apple Silicon Mac is left alone; its Bluetooth chip is a different generation"

home=$(run_leaf "LENOVO" 43ba 0)
[[ ! -f $(conf "$home") ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_migration() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" home="$4"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" HOME="$home" \
    OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    bash -euo pipefail "$migration" >/dev/null
}

home="$test_tmp/migrate-home"
rm -rf "$home"
mkdir -p "$home"
run_migration "Apple Inc." 43ba 0 "$home"
diff -q "$(conf "$home")" "$fragment" >/dev/null 2>&1 ||
  fail "the migration fixes an install that never got the codec cap" "$(ls -R "$home" 2>&1)"
grep -Fq 'omarchy-restart-audio' "$calls" ||
  fail "the migration restarts audio so the cap applies to the running session" "$(cat "$calls")"
pass "the migration fixes an install and restarts audio to apply it now"

run_migration "Apple Inc." 43ba 0 "$home"
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

home="$test_tmp/skip-home"
rm -rf "$home"
mkdir -p "$home"
run_migration "LENOVO" 43ba 0 "$home"
[[ ! -e $(conf "$home") ]] || fail "the migration skips non-Apple hardware" "$(cat "$(conf "$home")")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected hardware" "$(cat "$calls")"
pass "the migration skips hardware without the combo Broadcom chip"
