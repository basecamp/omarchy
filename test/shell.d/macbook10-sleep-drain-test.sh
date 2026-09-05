#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply="$ROOT/bin/omarchy-hw-macbook10-sleep-drain"
leaf="$ROOT/install/hardware/apple/fix-macbook10-sleep-drain.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788600200.sh"

grep -q 'apple/fix-macbook10-sleep-drain.sh' "$all" ||
  fail "the MacBook10,1 sleep-drain fix runs during hardware setup"
pass "the MacBook10,1 sleep-drain fix runs during hardware setup"

grep -q 'fix-macbook10-sleep-drain.sh' "$migration" ||
  fail "a migration applies the sleep-drain fix on existing installs"
pass "a migration applies the sleep-drain fix on existing installs"

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

fake_sysfs() {
  local root=$1 product=${2:-MacBook10,1} wakeup=${3:-enabled}
  mkdir -p "$root/sys/class/dmi/id" \
    "$root/sys/bus/pci/devices/0000:02:00.0/power"
  printf '%s\n' "$product" >"$root/sys/class/dmi/id/product_name"
  printf '0x14e4\n' >"$root/sys/bus/pci/devices/0000:02:00.0/vendor"
  printf '0x43a3\n' >"$root/sys/bus/pci/devices/0000:02:00.0/device"
  printf '%s\n' "$wakeup" >"$root/sys/bus/pci/devices/0000:02:00.0/power/wakeup"
}

sys="$test_tmp/sysfs"
acpi="$test_tmp/acpi-wakeup"
fake_sysfs "$sys"
cat >"$acpi" <<'EOF'
Device	S-state	  Status   Sysfs node
ARPT	  S4	*enabled   pci:0000:02:00.0
LID0	  S4	*enabled   platform:PNP0C0D:00
EOF

OMARCHY_SYSFS_ROOT="$sys" OMARCHY_ACPI_WAKEUP="$acpi" bash "$apply"
[[ $(cat "$sys/sys/bus/pci/devices/0000:02:00.0/power/wakeup") == disabled ]] ||
  fail "apply disables BCM4350 PCI wakeup"
[[ $(cat "$acpi") == ARPT ]] || fail "apply toggles ACPI ARPT when it was enabled" "$(cat "$acpi")"
pass "apply disables Wi-Fi PCI and ACPI wakeup"

fake_sysfs "$sys"
cat >"$acpi" <<'EOF'
Device	S-state	  Status   Sysfs node
ARPT	  S4	*disabled  pci:0000:02:00.0
EOF
before=$(cat "$acpi")
OMARCHY_SYSFS_ROOT="$sys" OMARCHY_ACPI_WAKEUP="$acpi" bash "$apply"
[[ $(cat "$acpi") == "$before" ]] || fail "apply leaves ARPT alone when it is already disabled"
pass "apply is idempotent when ARPT is already disabled"

other="$test_tmp/other"
fake_sysfs "$other" "MacBookPro14,1"
printf 'enabled\n' >"$other/sys/bus/pci/devices/0000:02:00.0/power/wakeup"
OMARCHY_SYSFS_ROOT="$other" OMARCHY_ACPI_WAKEUP="$acpi" bash "$apply"
[[ $(cat "$other/sys/bus/pci/devices/0000:02:00.0/power/wakeup") == enabled ]] ||
  fail "apply leaves unrelated hardware wakeup unchanged"
pass "apply is a no-op off MacBook10,1"

status=$(OMARCHY_SYSFS_ROOT="$sys" OMARCHY_ACPI_WAKEUP="$acpi" bash "$apply" status)
[[ $status == *wakeup=disabled* ]] || fail "status reports disabled PCI wakeup" "$status"
[[ $status == *acpi_arpt=disabled* ]] || fail "status reports disabled ARPT" "$status"
pass "status reports the applied wakeup disable"

udev="$test_tmp/99-omarchy-macbook10-wifi-wakeup.rules"
unit="$test_tmp/omarchy-macbook10-sleep-drain.service"
hook="$test_tmp/sleep-hook"
logind="$test_tmp/30-macbook10-suspend-then-hibernate.conf"
sleep_conf="$test_tmp/30-macbook10-hibernate-delay.conf"
resume="$test_tmp/omarchy_resume.conf"
drain_copy="$test_tmp/omarchy-hw-macbook10-sleep-drain"
cp "$apply" "$drain_copy"
chmod +x "$drain_copy"

run_leaf() {
  : >"$calls"
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_PRODUCT_NAME="$1" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_MACBOOK10_SLEEP_UDEV="$udev" \
    OMARCHY_MACBOOK10_SLEEP_UNIT="$unit" \
    OMARCHY_MACBOOK10_SLEEP_HOOK="$hook" \
    OMARCHY_MACBOOK10_SLEEP_BIN="$drain_copy" \
    OMARCHY_MACBOOK10_SLEEP_LOGIND="$logind" \
    OMARCHY_MACBOOK10_SLEEP_CONF="$sleep_conf" \
    OMARCHY_MACBOOK10_RESUME_CONF="$2" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf"
}

rm -f "$udev" "$unit" "$hook" "$logind" "$sleep_conf"
run_leaf "MacBookPro14,1" "$resume"
[[ ! -f $udev ]] || fail "setup skips unrelated hardware"
[[ ! -s $calls ]] || fail "setup escalates nothing on unrelated hardware" "$(cat "$calls")"
pass "setup skips unrelated hardware"

run_leaf "MacBook10,1" "$test_tmp/missing-resume.conf"
[[ -f $udev ]] || fail "setup writes the udev rule"
grep -Fq 'ATTR{device}=="0x43a3"' "$udev" || fail "the udev rule matches BCM4350" "$(cat "$udev")"
[[ -f $unit ]] || fail "setup writes the systemd unit"
grep -Fq "ExecStart=$drain_copy" "$unit" ||
  fail "the unit runs the sleep-drain command" "$(cat "$unit")"
[[ -x $hook ]] || fail "setup installs an executable sleep hook"
grep -Fq "exec \"$drain_copy\"" "$hook" ||
  fail "the sleep hook re-applies the wakeup disable" "$(cat "$hook")"
[[ ! -f $logind ]] || fail "setup does not change the lid action"
grep -Fq $'systemctl\tenable\t--now\tomarchy-macbook10-sleep-drain.service' "$calls" ||
  fail "setup enables the sleep-drain service" "$(cat "$calls")"
pass "setup installs wakeup disable and leaves lid-close as S3"

printf 'HandleLidSwitch=suspend-then-hibernate\n' >"$logind"
printf 'HibernateDelaySec=30min\n' >"$sleep_conf"
run_leaf "MacBook10,1" "$resume"
[[ ! -f $logind ]] || fail "setup removes a previous hibernate-on-lid drop-in"
[[ ! -f $sleep_conf ]] || fail "setup removes a previous hibernate delay drop-in"
grep -Fq $'systemctl\treload\tsystemd-logind' "$calls" ||
  fail "setup reloads logind after removing hibernate-on-lid" "$(cat "$calls")"
pass "setup removes a previous hibernate-on-lid policy"

: >"$calls"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_PRODUCT_NAME="MacBook10,1" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_MACBOOK10_SLEEP_UDEV="$udev" \
  OMARCHY_MACBOOK10_SLEEP_UNIT="$unit" \
  OMARCHY_MACBOOK10_SLEEP_HOOK="$hook" \
  OMARCHY_MACBOOK10_SLEEP_BIN="$drain_copy" \
  OMARCHY_MACBOOK10_SLEEP_LOGIND="$logind" \
  OMARCHY_MACBOOK10_SLEEP_CONF="$sleep_conf" \
  OMARCHY_MACBOOK10_RESUME_CONF="$resume" \
  bash -euo pipefail "$migration"
grep -Fq $'systemctl\tenable\t--now\tomarchy-macbook10-sleep-drain.service' "$calls" ||
  fail "the migration runs hardware setup" "$(cat "$calls")"
pass "the migration runs hardware setup"
