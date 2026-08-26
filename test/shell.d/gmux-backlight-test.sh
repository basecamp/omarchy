#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-gmux-backlight.sh"
rule="$ROOT/default/udev/gmux-backlight.rules"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787689809.sh"

grep -q 'apple/fix-gmux-backlight.sh' "$all" ||
  fail "the gmux backlight quirk runs during hardware setup"
pass "the gmux backlight quirk runs during hardware setup"

grep -Fq 'ENV{SYSTEMD_WANTS}+="systemd-backlight@backlight:gmux_backlight.service"' "$rule" ||
  fail "the udev rule starts systemd-backlight for gmux_backlight"
! grep -Fq 'IMPORT{builtin}="path_id"' "$rule" ||
  fail "the udev rule must not depend on path_id"
pass "the udev rule starts systemd-backlight without path_id"

grep -q 'fix-gmux-backlight.sh' "$migration" ||
  fail "the migration applies the gmux backlight quirk" "$migration"
pass "the migration applies the gmux backlight quirk"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
rules_dir="$test_tmp/etc/udev/rules.d"
dest="$rules_dir/99-omarchy-gmux-backlight.rules"
mkdir -p "$stub_bin" "$test_tmp/dmi" "$test_tmp/backlight"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/udevadm" <<'SH'
#!/bin/bash

printf 'udevadm' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local vendor="$1" gmux="${2:-0}" keep="${3:-0}"
  if (( keep == 0 )); then
    rm -rf "$test_tmp/etc" "$test_tmp/backlight"
    mkdir -p "$test_tmp/etc" "$test_tmp/backlight"
  fi
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  if (( gmux == 1 )); then
    mkdir -p "$test_tmp/backlight/gmux_backlight"
  fi
  : >"$calls"

  OMARCHY_PATH="$ROOT" \
    OMARCHY_UDEV_RULES_DIR="$rules_dir" \
    OMARCHY_BACKLIGHT_PATH="$test_tmp/backlight" \
    OMARCHY_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf" </dev/null
}

run_leaf "Apple Inc." 1 >/dev/null
[[ -f $dest ]] || fail "a Mac with gmux gets the udev rule" "$(ls -R "$test_tmp/etc" 2>&1)"
diff -q "$rule" "$dest" >/dev/null ||
  fail "the installed udev rule matches the packaged source"
grep -Fq $'udevadm\tcontrol\t--reload-rules' "$calls" ||
  fail "a live session reloads udev" "$(cat "$calls")"
grep -Fq $'systemctl\tstart\tsystemd-backlight@backlight:gmux_backlight.service' "$calls" ||
  fail "a live session starts systemd-backlight" "$(cat "$calls")"
pass "a Mac with gmux gets the udev rule"

# ISO-time apple_gmux may not have registered yet; still drop the rule so first
# boot can start systemd-backlight when the device appears.
run_leaf "Apple Inc." 0 >/dev/null
[[ -f $dest ]] || fail "an Apple machine without gmux sysfs still gets the rule"
pass "an Apple machine without gmux sysfs still gets the rule"

run_leaf "Apple Computer, Inc." 0 >/dev/null
[[ -f $dest ]] || fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

run_leaf "LENOVO" 0 >/dev/null
[[ ! -f $dest ]] || fail "non-Apple hardware without gmux is left alone"
[[ ! -s $calls ]] || fail "non-Apple hardware escalates nothing" "$(cat "$calls")"
pass "non-Apple hardware without gmux is left alone"

run_leaf "LENOVO" 1 >/dev/null
[[ -f $dest ]] || fail "a gmux device on unexpected vendor still gets the rule"
pass "a gmux device on unexpected vendor still gets the rule"

run_leaf "Apple Inc." 1 >/dev/null
printf 'keep me\n' >"$dest"
run_leaf "Apple Inc." 1 1 >/dev/null
[[ $(<"$dest") == "keep me" ]] || fail "an existing udev rule is not overwritten"
grep -Fq $'systemctl\tstart\tsystemd-backlight@backlight:gmux_backlight.service' "$calls" ||
  fail "a second run still starts systemd-backlight" "$(cat "$calls")"
pass "an existing udev rule is left in place"

run_migration() {
  local vendor="$1" gmux="${2:-0}"
  rm -rf "$test_tmp/etc" "$test_tmp/backlight"
  mkdir -p "$test_tmp/etc" "$test_tmp/backlight"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  if (( gmux == 1 )); then
    mkdir -p "$test_tmp/backlight/gmux_backlight"
  fi
  : >"$calls"

  OMARCHY_PATH="$ROOT" \
    OMARCHY_UDEV_RULES_DIR="$rules_dir" \
    OMARCHY_BACKLIGHT_PATH="$test_tmp/backlight" \
    OMARCHY_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration "Apple Inc." 1
[[ -f $dest ]] || fail "the migration installs the udev rule on a Mac with gmux"
pass "the migration installs the udev rule on a Mac with gmux"

run_migration "LENOVO" 0
[[ ! -f $dest ]] || fail "the migration skips non-Apple hardware without gmux"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected hardware" "$(cat "$calls")"
pass "the migration skips hardware without gmux"
