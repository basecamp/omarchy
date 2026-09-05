#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-macbook10"
apply="$ROOT/bin/omarchy-hw-macbook10-power-envelope"
leaf="$ROOT/install/hardware/apple/fix-macbook10-power-envelope.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788380505.sh"

grep -q 'apple/fix-macbook10-power-envelope.sh' "$all" ||
  fail "the MacBook10,1 power envelope runs during hardware setup"
pass "the MacBook10,1 power envelope runs during hardware setup"

grep -q 'fix-macbook10-power-envelope.sh' "$migration" ||
  fail "a migration applies the envelope on existing installs"
pass "a migration applies the envelope on existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-hw-match" <<'SH'
#!/bin/bash
[[ ${TEST_PRODUCT_NAME:-} == *"$1"* ]]
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_detector() {
  PATH="$stub_bin:$PATH" TEST_PRODUCT_NAME="$1" bash "$detector"
}

run_detector "MacBook10,1" || fail "the detector matches MacBook10,1"
pass "the detector matches MacBook10,1"

run_detector "MacBookPro14,1" && fail "the detector rejects a MacBook Pro"
pass "the detector rejects a MacBook Pro"

run_detector "MacBook9,1" && fail "the detector rejects the 2016 12-inch"
pass "the detector rejects the 2016 12-inch"

fake_sysfs() {
  local root=$1 product=${2:-MacBook10,1}
  mkdir -p "$root/sys/class/dmi/id" \
    "$root/sys/class/powercap/intel-rapl:0" \
    "$root/sys/devices/system/cpu/cpu0/cpufreq" \
    "$root/sys/devices/system/cpu/cpu1/cpufreq" \
    "$root/sys/devices/system/cpu/intel_pstate" \
    "$root/sys/class/thermal/thermal_zone0"
  printf '%s\n' "$product" >"$root/sys/class/dmi/id/product_name"
  printf '49000000\n' >"$root/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"
  printf '49000000\n' >"$root/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw"
  printf '27983872\n' >"$root/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us"
  printf '2440\n' >"$root/sys/class/powercap/intel-rapl:0/constraint_1_time_window_us"
  printf '1\n' >"$root/sys/class/powercap/intel-rapl:0/enabled"
  printf '3600000\n' >"$root/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
  printf '3600000\n' >"$root/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
  printf '1300000\n' >"$root/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
  printf '3600000\n' >"$root/sys/devices/system/cpu/cpu1/cpufreq/cpuinfo_max_freq"
  printf '3600000\n' >"$root/sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq"
  printf '100\n' >"$root/sys/devices/system/cpu/intel_pstate/max_perf_pct"
  printf '63000\n' >"$root/sys/class/thermal/thermal_zone0/temp"
}

sys="$test_tmp/sysfs"
fake_sysfs "$sys"

OMARCHY_SYSFS_ROOT="$sys" bash "$apply"
[[ $(cat "$sys/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw") == 4500000 ]] ||
  fail "apply writes PL1 4.5W"
[[ $(cat "$sys/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw") == 7000000 ]] ||
  fail "apply writes PL2 7W"
[[ $(cat "$sys/sys/class/powercap/intel-rapl:0/constraint_1_time_window_us") == 2000000 ]] ||
  fail "apply sets a multi-second PL2 window"
[[ $(cat "$sys/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq") == 3000000 ]] ||
  fail "apply caps CPU0 at 3GHz"
[[ $(cat "$sys/sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq") == 3000000 ]] ||
  fail "apply caps CPU1 at 3GHz"
[[ $(cat "$sys/sys/devices/system/cpu/intel_pstate/max_perf_pct") == 83 ]] ||
  fail "apply sets max_perf_pct to 83"
pass "apply writes the 4.5W/7W RAPL cap and 3GHz CPU ceiling"

other="$test_tmp/other"
fake_sysfs "$other" "MacBookPro14,1"
OMARCHY_SYSFS_ROOT="$other" bash "$apply"
[[ $(cat "$other/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw") == 49000000 ]] ||
  fail "apply leaves unrelated hardware RAPL unchanged"
[[ $(cat "$other/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq") == 3600000 ]] ||
  fail "apply leaves unrelated hardware frequency unchanged"
pass "apply is a no-op off MacBook10,1"

status=$(OMARCHY_SYSFS_ROOT="$sys" bash "$apply" status)
[[ $status == *pl1_uw=4500000* ]] || fail "status reports the applied PL1" "$status"
[[ $status == *cpu0_scaling_max_khz=3000000* ]] || fail "status reports the applied CPU cap" "$status"
pass "status reports the applied envelope"

unit="$test_tmp/omarchy-macbook10-power-envelope.service"
hook="$test_tmp/sleep-hook"
envelope_copy="$test_tmp/omarchy-hw-macbook10-power-envelope"
cp "$apply" "$envelope_copy"
chmod +x "$envelope_copy"

run_leaf() {
  : >"$calls"
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_PRODUCT_NAME="$1" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_MACBOOK10_ENVELOPE_UNIT="$unit" \
    OMARCHY_MACBOOK10_ENVELOPE_SLEEP_HOOK="$hook" \
    OMARCHY_MACBOOK10_ENVELOPE_BIN="$envelope_copy" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf"
}

rm -f "$unit" "$hook"
run_leaf "MacBookPro14,1"
[[ ! -f $unit ]] || fail "setup skips unrelated hardware"
[[ ! -s $calls ]] || fail "setup escalates nothing on unrelated hardware" "$(cat "$calls")"
pass "setup skips unrelated hardware"

run_leaf "MacBook10,1"
[[ -f $unit ]] || fail "setup writes the systemd unit"
grep -Fq "ExecStart=$envelope_copy" "$unit" ||
  fail "the unit runs the envelope command" "$(cat "$unit")"
[[ -x $hook ]] || fail "setup installs an executable resume hook"
grep -Fq "exec \"$envelope_copy\"" "$hook" ||
  fail "the resume hook re-applies the envelope" "$(cat "$hook")"
grep -Fq $'systemctl\tenable\t--now\tomarchy-macbook10-power-envelope.service' "$calls" ||
  fail "setup enables the envelope service" "$(cat "$calls")"
pass "setup installs the boot unit and resume hook"

: >"$calls"
run_leaf "MacBook10,1"
grep -Fq $'systemctl\tenable\t--now\tomarchy-macbook10-power-envelope.service' "$calls" ||
  fail "setup remains idempotent" "$(cat "$calls")"
pass "setup remains idempotent"

: >"$calls"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_PRODUCT_NAME="MacBook10,1" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_MACBOOK10_ENVELOPE_UNIT="$unit" \
  OMARCHY_MACBOOK10_ENVELOPE_SLEEP_HOOK="$hook" \
  OMARCHY_MACBOOK10_ENVELOPE_BIN="$envelope_copy" \
  bash -euo pipefail "$migration"
grep -Fq $'systemctl\tenable\t--now\tomarchy-macbook10-power-envelope.service' "$calls" ||
  fail "the migration runs hardware setup" "$(cat "$calls")"
pass "the migration runs hardware setup"
