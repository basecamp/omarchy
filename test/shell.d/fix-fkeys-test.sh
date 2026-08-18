#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-fkeys.sh"
fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787019665.sh"

grep -q 'hardware/fix-fkeys.sh' "$all" ||
  fail "F-key hid_apple setup still runs during hardware setup"
[[ -f $fix_t2 ]] || fail "T2 setup script is present"
if grep -q 'fnmode=2' "$fix_t2"; then
  fail "T2 setup does not own hid_apple fnmode"
fi
pass "F-key hid_apple setup has a single owner and runs during setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/hid_apple.conf"
dmi_vendor="$test_tmp/dmi/sys_vendor"
mkdir -p "$stub_bin" "$test_tmp/dmi" "$(dirname "$conf")"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

[[ $1 == limine-mkinitcpio ]] && (( ${LIMINE_MKINITCPIO:-1} == 1 ))
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local vendor="$1"
  local existing="${2-}"
  rm -rf "$test_tmp/etc"
  mkdir -p "$(dirname "$conf")"
  printf '%s' "$vendor" >"$dmi_vendor"
  if [[ -n $existing ]]; then
    printf '%s' "$existing" >"$conf"
  fi

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_HID_APPLE_DMI_VENDOR="$dmi_vendor" \
    OMARCHY_HID_APPLE_CONF="$conf" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf" </dev/null
}

run_migration() {
  local vendor="$1"
  printf '%s' "$vendor" >"$dmi_vendor"
  : >"$calls"

  T2_HARDWARE="${T2_HARDWARE:-0}" LIMINE_MKINITCPIO="${LIMINE_MKINITCPIO:-1}" \
    PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_HID_APPLE_DMI_VENDOR="$dmi_vendor" \
    OMARCHY_HID_APPLE_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null
}

run_leaf "LENOVO"
[[ -f $conf ]] || fail "a non-Apple machine still gets the Lofree drop-in"
grep -qx 'options hid_apple fnmode=2' "$conf" ||
  fail "the non-Apple drop-in is the hid_apple fnmode=2 line" "$(cat "$conf")"
pass "a non-Apple machine still gets the Lofree drop-in"

run_leaf "QEMU"
[[ -f $conf ]] || fail "a VM without Apple DMI still gets the drop-in"
pass "a VM without Apple DMI still gets the drop-in"

run_leaf "Apple Inc."
[[ ! -f $conf ]] || fail "an Apple machine is left on kernel default" "$(cat "$conf")"
pass "an Apple machine is left on kernel default"

run_leaf "Apple Computer, Inc."
[[ ! -f $conf ]] || fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

run_leaf "Apple Inc." $'options hid_apple fnmode=2\n'
[[ ! -e $conf ]] || fail "apply-hardware removes the stock Apple drop-in" "$(cat "$conf")"
pass "apply-hardware removes the stock Apple drop-in"

run_leaf "Apple Inc." $'options hid_apple fnmode=2\noptions hid_apple iso_layout=1\n'
grep -qx 'options hid_apple fnmode=2' "$conf" ||
  fail "a customized hid_apple.conf is left alone" "$(cat "$conf")"
pass "a customized hid_apple.conf is left alone"

run_leaf "LENOVO" $'options hid_apple swap_opt_cmd=1\n'
grep -qx 'options hid_apple swap_opt_cmd=1' "$conf" ||
  fail "an existing non-Apple hid_apple.conf is not overwritten" "$(cat "$conf")"
! grep -q 'fnmode=2' "$conf" ||
  fail "an existing non-Apple hid_apple.conf is not appended to" "$(cat "$conf")"
pass "an existing non-Apple hid_apple.conf is left untouched"

# Installs that predate the gate already have the drop-in.
printf 'options hid_apple fnmode=2\n' >"$conf"
T2_HARDWARE=0 run_migration "Apple Inc."
[[ ! -e $conf ]] || fail "the migration removes the stock Apple drop-in" "$(cat "$conf")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
! grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a non-T2 Apple machine does not rebuild the boot image" "$(cat "$calls")"
pass "the migration removes the stock drop-in on Apple hardware"

printf 'options hid_apple fnmode=2\n' >"$conf"
T2_HARDWARE=1 run_migration "Apple Inc."
[[ ! -e $conf ]] || fail "the migration removes the stock T2 drop-in" "$(cat "$conf")"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a T2 Mac rebuilds the initramfs that bakes in hid_apple" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "a T2 Mac still asks for a reboot" "$(cat "$calls")"
pass "the migration rebuilds the T2 initramfs after removing the drop-in"

printf 'options hid_apple fnmode=2\n' >"$conf"
T2_HARDWARE=1 LIMINE_MKINITCPIO=0 run_migration "Apple Inc."
[[ ! -e $conf ]] || fail "the migration still removes the drop-in without limine-mkinitcpio"
! grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a missing limine-mkinitcpio is not invoked" "$(cat "$calls")"
pass "the T2 rebuild is skipped when limine-mkinitcpio is absent"

printf 'options hid_apple fnmode=2\n' >"$conf"
: >"$calls"
T2_HARDWARE=0 run_migration "Apple Inc."
T2_HARDWARE=0 run_migration "Apple Inc."
[[ ! -e $conf ]] || fail "a second migration run keeps the file gone"
[[ ! -s $calls ]] || fail "an already repaired Apple install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

printf 'options hid_apple fnmode=2\noptions hid_apple iso_layout=1\n' >"$conf"
T2_HARDWARE=0 run_migration "Apple Inc."
grep -qx 'options hid_apple fnmode=2' "$conf" ||
  fail "the migration keeps a customized Apple hid_apple.conf" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "a customized Apple config escalates nothing" "$(cat "$calls")"
pass "the migration leaves a customized Apple hid_apple.conf alone"

printf 'options hid_apple fnmode=2\n' >"$conf"
T2_HARDWARE=0 run_migration "LENOVO"
grep -qx 'options hid_apple fnmode=2' "$conf" ||
  fail "the migration keeps the Lofree drop-in on non-Apple hardware" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "non-Apple hardware escalates nothing" "$(cat "$calls")"
pass "the migration leaves non-Apple hardware on fnmode=2"
