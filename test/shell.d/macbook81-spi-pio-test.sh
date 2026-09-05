#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788318101.sh"

grep -q 'apple/fix-spi-keyboard.sh' "$all" ||
  fail "the SPI keyboard leaf runs during hardware setup"
grep -q 'initcall_blacklist=dw_pci_driver_init' "$leaf" ||
  fail "MacBook8,1 setup forces SPI PIO"
grep -q 'mem_sleep_default=s2idle' "$leaf" ||
  fail "MacBook8,1 setup defaults sleep to s2idle"
pass "MacBook8,1 SPI PIO is part of hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$test_tmp/dmi"
: >"$calls"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
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

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local product="$1"
  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$product" >"$test_tmp/dmi/product_name"
  : >"$calls"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/product_name|$test_tmp/dmi/product_name|g" \
      -e "s|/etc/mkinitcpio.conf.d|$test_tmp/etc/mkinitcpio.conf.d|g" \
      -e "s|/etc/limine-entry-tool.d|$test_tmp/etc/limine-entry-tool.d|g" \
      "$leaf" >"$script"

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf "MacBook8,1" >/dev/null
modules="$test_tmp/etc/mkinitcpio.conf.d/macbook_spi_modules.conf"
pio="$test_tmp/etc/limine-entry-tool.d/macbook81-spi-pio.conf"
grep -Fq 'MODULES=(applespi spi_pxa2xx_platform spi_pxa2xx_pci)' "$modules" ||
  fail "MacBook8,1 still gets the SPI initramfs modules" "$(cat "$modules" 2>/dev/null)"
grep -Fq 'initcall_blacklist=dw_pci_driver_init' "$pio" ||
  fail "MacBook8,1 gets the PIO kernel parameter" "$(cat "$pio" 2>/dev/null)"
grep -Fq 'mem_sleep_default=s2idle' "$pio" ||
  fail "MacBook8,1 gets s2idle" "$(cat "$pio" 2>/dev/null)"
grep -Fq $'omarchy-pkg-add\tmacbook12-spi-driver-dkms' "$calls" ||
  fail "MacBook8,1 still installs the SPI DKMS package" "$(cat "$calls")"
pass "MacBook8,1 setup writes SPI modules and the PIO drop-in"

run_leaf "MacBook10,1" >/dev/null
[[ -f $modules ]] || fail "MacBook10,1 still gets SPI modules"
[[ ! -e $pio ]] || fail "later 12-inch MacBooks do not get the 8,1 PIO quirk" "$(cat "$pio")"
pass "later SPI MacBooks are left on DMA"

run_leaf "MacBookPro14,1" >/dev/null
[[ ! -e $pio ]] || fail "MacBookPro models do not get the 8,1 PIO quirk"
pass "MacBookPro SPI models are left on DMA"

run_leaf "ThinkPad X1 Carbon" >/dev/null
[[ ! -e $modules ]] || fail "non-Apple hardware is left alone"
[[ ! -e $pio ]] || fail "non-Apple hardware is left alone"
[[ ! -s $calls ]] || fail "non-Apple hardware escalates nothing" "$(cat "$calls")"
pass "non-Apple hardware is left alone"

run_migration() {
  local product="$1"
  printf '%s' "$product" >"$test_tmp/dmi/product_name"
  : >"$calls"

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_MACBOOK81_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_MACBOOK81_LIMINE_CONF="$pio" \
    OMARCHY_MACBOOK81_REPAIR_MARKER="$test_tmp/repair-complete" \
    OMARCHY_MACBOOK81_RUNNING_CMDLINE="$test_tmp/cmdline" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc" "$test_tmp/repair-complete"
mkdir -p "$test_tmp/etc"
echo 'quiet splash' >"$test_tmp/cmdline"
run_migration "MacBook8,1"
grep -Fq 'initcall_blacklist=dw_pci_driver_init' "$pio" ||
  fail "the migration writes the PIO drop-in" "$(cat "$pio" 2>/dev/null)"
grep -Fq 'mem_sleep_default=s2idle' "$pio" ||
  fail "the migration writes s2idle" "$(cat "$pio" 2>/dev/null)"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the migration rebuilds the boot image" "$(cat "$calls")"
[[ -f $test_tmp/repair-complete ]] || fail "the migration records the machine-wide repair"
pass "the migration repairs an existing MacBook8,1"

: >"$calls"
run_migration "MacBook8,1"
[[ ! -s $calls ]] || fail "an already repaired MacBook8,1 is left unchanged" "$(cat "$calls")"
pass "the migration is machine-idempotent before reboot"

rm -f "$test_tmp/repair-complete"
: >"$calls"
run_migration "MacBook8,1"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the migration retries an interrupted boot image rebuild"
[[ -f $test_tmp/repair-complete ]] || fail "a retried repair records completion"
! grep -Eq $'^(sudo\t)?tee(\t|$)' "$calls" ||
  fail "rebuild retry leaves a complete drop-in alone" "$(cat "$calls")"
pass "the migration retries an interrupted boot image rebuild"

rm -rf "$test_tmp/etc" "$test_tmp/repair-complete"
mkdir -p "$test_tmp/etc"
: >"$calls"
run_migration "MacBook10,1"
[[ ! -e $pio ]] || fail "the migration skips later 12-inch MacBooks"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unrelated Macs" "$(cat "$calls")"
pass "the migration skips unrelated hardware"
