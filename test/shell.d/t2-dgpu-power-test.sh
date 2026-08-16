#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/install/hardware/apple/fix-t2-dgpu-power.sh"
service="$ROOT/default/systemd/system/omarchy-t2-dgpu-off.service"
migration="$ROOT/migrations/1786820569.sh"

grep -Fxq 'After=systemd-modules-load.service' "$service" ||
  fail "the T2 dGPU service waits for graphics modules"
grep -Fxq 'Before=display-manager.service' "$service" ||
  fail "the T2 dGPU service runs before the display manager"
grep -Fq 'force_igd=(y|Y|1)' "$service" ||
  fail "the T2 dGPU service only runs in integrated mode"
grep -Fq 'echo OFF > /sys/kernel/debug/vgaswitcheroo/switch' "$service" ||
  fail "the T2 dGPU service powers Radeon off through vga_switcheroo"
pass "the T2 dGPU service follows the selected graphics mode"

grep -Fq 'apple/fix-t2-dgpu-power.sh' "$ROOT/install/hardware/all.sh" ||
  fail "fresh installs run the T2 dGPU setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
service_path="$test_tmp/etc/systemd/system/omarchy-t2-dgpu-off.service"
repair_marker="$test_tmp/var/lib/omarchy/migrations/1786820569"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

if (( ${T2_HARDWARE:-0} )); then
  echo '04:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
if (( ${INTEL_GPU:-0} )); then
  echo '00:02.0 VGA compatible controller [0300]: Intel UHD Graphics [8086:3e9b]'
fi
if (( ${AMD_GPU:-0} )); then
  echo '03:00.0 VGA compatible controller [0300]: AMD Radeon Pro [1002:7340]'
fi
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

chmod +x "$stub_bin"/*

run_installer() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_DGPU_SERVICE_PATH="$service_path" \
    T2_HARDWARE="${T2_HARDWARE:-1}" \
    INTEL_GPU="${INTEL_GPU:-1}" \
    AMD_GPU="${AMD_GPU:-1}" \
    bash -euo pipefail "$installer"
}

run_installer

cmp -s "$service" "$service_path" ||
  fail "fresh hybrid T2 installs copy the dGPU service"
grep -Fxq $'systemctl\tenable\tomarchy-t2-dgpu-off.service' "$calls" ||
  fail "fresh hybrid T2 installs enable the dGPU service"
pass "fresh hybrid T2 installs enable automatic Radeon power-off"

rm -f "$service_path"
: >"$calls"
AMD_GPU=0 run_installer

[[ ! -e $service_path ]] || fail "iGPU-only T2 Macs skip the dGPU service"
[[ ! -s $calls ]] || fail "iGPU-only T2 Macs leave systemd unchanged" "$(cat "$calls")"
pass "iGPU-only T2 Macs skip Radeon power management"

: >"$calls"
T2_HARDWARE=0 run_installer

[[ ! -e $service_path ]] || fail "non-T2 hybrid laptops skip the dGPU service"
[[ ! -s $calls ]] || fail "non-T2 hybrid laptops leave systemd unchanged" "$(cat "$calls")"
pass "non-T2 hybrid laptops skip the T2-specific service"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_DGPU_SERVICE_PATH="$service_path" \
    OMARCHY_T2_DGPU_REPAIR_MARKER="$repair_marker" \
    T2_HARDWARE="${T2_HARDWARE:-1}" \
    INTEL_GPU="${INTEL_GPU:-1}" \
    AMD_GPU="${AMD_GPU:-1}" \
    bash -euo pipefail "$migration" >/dev/null
}

: >"$calls"
run_migration

cmp -s "$service" "$service_path" ||
  fail "the migration installs the dGPU service on existing hybrid T2 Macs"
grep -Fxq $'sudo\tsystemctl\tenable\tomarchy-t2-dgpu-off.service' "$calls" ||
  fail "the migration enables the dGPU service"
[[ -f $repair_marker ]] || fail "the migration records the machine-wide repair"
! grep -Eq $'systemctl\t(enable --now|start)' "$calls" ||
  fail "the migration waits until reboot to change GPU power"
pass "the migration prepares existing hybrid T2 Macs for the next boot"

: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "an already migrated machine is left unchanged" "$(cat "$calls")"
pass "the T2 dGPU migration is machine-idempotent"

rm -f "$repair_marker"
: >"$calls"
T2_HARDWARE=0 run_migration

[[ ! -e $repair_marker ]] || fail "non-T2 machines skip the dGPU migration"
[[ ! -s $calls ]] || fail "non-T2 machines migrate without privileged work" "$(cat "$calls")"
pass "the migration skips unrelated hardware without prompting"
