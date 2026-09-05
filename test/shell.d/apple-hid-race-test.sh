#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-asahi-hid-race.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788200001.sh"

grep -q 'apple/fix-asahi-hid-race.sh' "$all" ||
  fail "the HID early-load runs during hardware setup"
pass "the HID early-load runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/mkinitcpio.conf.d/apple_hid_modules.conf"
ready="$test_tmp/var/lib/omarchy/apple-hid-initramfs-ready"
mkdir -p "$stub_bin"

# Every command whose effect matters outside the tree gets a stub, so each case
# can say which machine it runs on and what the kernel builds rather than
# inherit the ones this suite happens to have.
cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash

[[ ${APPLE_SILICON:-0} == "1" ]]
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/mkinitcpio" <<'SH'
#!/bin/bash

printf 'mkinitcpio' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
exit "${MKINITCPIO_STATUS:-0}"
SH

# Stubbed rather than run: the real one would write the running user's state.
cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

# MODULES_PRESENT names the modules this kernel builds, so a kernel missing one
# can be tested on a machine that has both.
cat >"$stub_bin/modinfo" <<'SH'
#!/bin/bash

module="${!#}"
[[ " ${MODULES_PRESENT-hid_apple hid_magicmouse} " == *" $module "* ]]
SH

chmod +x "$stub_bin"/*

# The leaf writes an absolute path, so every case runs a copy pointed into the
# sandbox instead.
sed -e "s|/etc/mkinitcpio.conf.d|$test_tmp/etc/mkinitcpio.conf.d|g" \
  "$leaf" >"$test_tmp/leaf.sh"

run_leaf() {
  local apple_silicon="${1:-1}"

  rm -rf "$test_tmp/etc"
  : >"$calls"

  APPLE_SILICON="$apple_silicon" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$test_tmp/leaf.sh" </dev/null
}

run_leaf >/dev/null
[[ -f $conf ]] ||
  fail "an Apple Silicon Mac gets the drop-in" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "an Apple Silicon Mac gets the drop-in"

# Intel Macs have their own HID story, and no dockchannel-hid to race with.
run_leaf 0 >/dev/null
[[ ! -e $conf ]] ||
  fail "a Mac without Apple Silicon is left alone" "$(cat "$conf")"
pass "a Mac without Apple Silicon is left alone"

# mkinitcpio sources the drop-in while building the image and dies on a MODULES
# entry it cannot find, so what the file does when a driver is missing decides
# whether every later rebuild works -- kernel upgrades included.
source_conf() {
  local present="$1"

  MODULES_PRESENT="$present" PATH="$stub_bin:$PATH" bash -c '
    MODULES=(btrfs)
    source "$1"
    status=$?
    printf "%s\n" "$status" "${MODULES[*]}" "$(declare -p _omarchy_apple_hid_module 2>/dev/null || echo unset)"
  ' bash "$conf"
}

run_leaf >/dev/null
mapfile -t sourced < <(source_conf "hid_apple hid_magicmouse")
[[ ${sourced[0]} == "0" ]] ||
  fail "the drop-in sources cleanly" "status ${sourced[0]}"
[[ ${sourced[1]} == "btrfs hid_apple hid_magicmouse" ]] ||
  fail "both drivers are early-loaded where the kernel builds them" "MODULES=(${sourced[1]})"
[[ ${sourced[2]} == "unset" ]] ||
  fail "the drop-in leaves no variable behind in mkinitcpio's config" "${sourced[2]}"
pass "both drivers are early-loaded where the kernel builds them"

# A kernel with one of them built in, or gone: naming it anyway would fail the
# whole image, and taking both out would drop the driver that is still there.
mapfile -t sourced < <(source_conf "hid_apple")
[[ ${sourced[0]} == "0" ]] ||
  fail "a kernel missing one driver still sources cleanly" "status ${sourced[0]}"
[[ ${sourced[1]} == "btrfs hid_apple" ]] ||
  fail "a driver the kernel does not build is left out" "MODULES=(${sourced[1]})"
pass "a driver the kernel does not build is left out"

mapfile -t sourced < <(source_conf "")
[[ ${sourced[0]} == "0" ]] ||
  fail "a kernel building neither driver still sources cleanly" "status ${sourced[0]}"
[[ ${sourced[1]} == "btrfs" ]] ||
  fail "neither driver is named when the kernel builds neither" "MODULES=(${sourced[1]})"
pass "a kernel building neither driver still sources cleanly"

# Installs that predate the leaf never ran it, so the migration has to reach
# them. omarchy-migrate runs migrations under bash -euo pipefail.
run_migration() {
  local apple_silicon="${1:-1}" mkinitcpio_status="${2:-0}"

  : >"$calls"

  APPLE_SILICON="$apple_silicon" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    MKINITCPIO_STATUS="$mkinitcpio_status" \
    OMARCHY_PATH="$test_tmp/omarchy" OMARCHY_APPLE_HID_CONF="$conf" \
    OMARCHY_APPLE_HID_READY="$ready" \
    bash -euo pipefail "$migration"
}

# The migration sources the leaf out of OMARCHY_PATH, so the sandbox needs the
# redirected copy where an install keeps it.
mkdir -p "$test_tmp/omarchy/install/hardware/apple"
cp "$test_tmp/leaf.sh" "$test_tmp/omarchy/install/hardware/apple/fix-asahi-hid-race.sh"

rm -rf "$test_tmp/etc"
run_migration >/dev/null
[[ -f $conf ]] ||
  fail "the migration fixes an install that never ran the leaf" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq $'mkinitcpio\t-P' "$calls" ||
  fail "the migration rebuilds the initramfs that carries MODULES" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
[[ -f $ready ]] ||
  fail "the migration records a successful initramfs rebuild" "$(cat "$calls")"
pass "the migration fixes an install that never ran the leaf"

run_migration >/dev/null
[[ ! -s $calls ]] ||
  fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

# A failed rebuild leaves the running initramfs as it was, so there is nothing
# for a reboot to apply.
rm -rf "$test_tmp/etc"
rm -f "$ready"
if run_migration 1 1 >/dev/null 2>&1; then
  fail "a failed rebuild leaves the migration pending"
fi
grep -Fq $'mkinitcpio\t-P' "$calls" ||
  fail "a failed rebuild is still attempted" "$(cat "$calls")"
if grep -Fq 'omarchy-state' "$calls"; then
  fail "a failed rebuild does not ask for a reboot" "$(cat "$calls")"
fi
[[ ! -e $ready ]] ||
  fail "a failed rebuild does not record success" "$(cat "$calls")"
run_migration >/dev/null
grep -Fq $'mkinitcpio\t-P' "$calls" ||
  fail "a failed rebuild is retried" "$(cat "$calls")"
[[ -f $ready ]] ||
  fail "a successful retry records the rebuilt initramfs" "$(cat "$calls")"
pass "a failed rebuild remains pending and retries"

rm -rf "$test_tmp/etc"
rm -f "$ready"
run_migration 0 >/dev/null
[[ ! -e $conf ]] ||
  fail "the migration skips hardware without the race" "$(cat "$conf")"
if grep -Fq 'mkinitcpio' "$calls"; then
  fail "the migration rebuilds nothing without Apple Silicon" "$(cat "$calls")"
fi
pass "the migration skips hardware without the race"
