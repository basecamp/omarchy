#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-gmux"
helpers="$ROOT/install/hardware/apple/gmux-backlight.sh"
fix="$ROOT/install/hardware/apple/fix-gmux-backlight.sh"
udev_src="$ROOT/default/udev/apple-gmux-backlight.rules"
migration="$ROOT/migrations/1788392890.sh"

assert_hw() {
  local path=$1 expect=$2 description=$3
  if OMARCHY_GMUX_BACKLIGHT="$path" "$hw"; then
    [[ $expect == yes ]] || fail "$description"
  else
    [[ $expect == no ]] || fail "$description"
  fi
  pass "$description"
}

missing=$(mktemp -u)
assert_hw "$missing" no "missing gmux_backlight is not apple-gmux"
present=$(mktemp)
assert_hw "$present" yes "present gmux_backlight is apple-gmux"
rm -f "$present"

grep -Fq 'IMPORT{builtin}="path_id"' "$udev_src" && fail "udev rule must not import path_id"
grep -Fq 'systemd-backlight@backlight:gmux_backlight.service' "$udev_src" ||
  fail "udev rule attaches systemd-backlight to gmux_backlight"
grep -Fq 'TAG+="systemd"' "$udev_src" || fail "udev rule tags the device for systemd"
pass "udev rule attaches systemd-backlight without path_id"

grep -Fq 'fix-gmux-backlight.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the gmux backlight hook with the other Apple hooks"
pass "gmux backlight install hook is wired"

# shellcheck source=../../install/hardware/apple/gmux-backlight.sh
OMARCHY_PATH="$ROOT" source "$helpers"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

etc="$test_tmp/etc"
mkdir -p "$etc/udev/rules.d"
OMARCHY_PATH="$ROOT"
OMARCHY_GMUX_UDEV_SRC="$udev_src"
OMARCHY_GMUX_UDEV_DEST="$etc/udev/rules.d/90-apple-gmux-backlight.rules"

gmux_install_rule
cmp -s "$udev_src" "$OMARCHY_GMUX_UDEV_DEST" || fail "install copies the packaged udev rule"
pass "helper installs the packaged udev rule"

gmux_activate
pass "activate is a no-op when dest is not under /etc/udev/rules.d"

dmi_missing="$test_tmp/no-gmux"
PATH="$ROOT/bin:$PATH" \
  OMARCHY_GMUX_BACKLIGHT="$dmi_missing" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_GMUX_UDEV_DEST="$test_tmp/should-not-exist.rules" \
  bash -c 'source "$1"' _ "$fix"
[[ ! -e $test_tmp/should-not-exist.rules ]] || fail "non-gmux install hook wrote a udev rule"
pass "install hook no-ops without gmux_backlight"

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/omarchy-hw-apple-gmux" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin"/*

install_etc="$test_tmp/install-etc"
mkdir -p "$install_etc/udev/rules.d"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_GMUX_UDEV_SRC="$udev_src" \
  OMARCHY_GMUX_UDEV_DEST="$install_etc/udev/rules.d/90-apple-gmux-backlight.rules" \
  bash -c 'source "$1"' _ "$fix"
cmp -s "$udev_src" "$install_etc/udev/rules.d/90-apple-gmux-backlight.rules" ||
  fail "install hook writes the udev rule on gmux hardware"
pass "install hook writes the udev rule on gmux hardware"

cat >"$stub_bin/omarchy-hw-apple-gmux" <<'SH'
#!/bin/bash
exit 1
SH
calls="$test_tmp/calls.log"
: >"$calls"
PATH="$stub_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration"
[[ ! -s $calls ]] || fail "non-gmux migration is a no-op" "$(cat "$calls")"
pass "migration skips unrelated hardware"

cat >"$stub_bin/omarchy-hw-apple-gmux" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
SH
chmod +x "$stub_bin/sudo"

migrate_etc="$test_tmp/migrate-etc"
mkdir -p "$migrate_etc/udev/rules.d"
: >"$calls"
PATH="$stub_bin:$PATH" \
  CALLS="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_GMUX_UDEV_SRC="$udev_src" \
  OMARCHY_GMUX_UDEV_DEST="$migrate_etc/udev/rules.d/90-apple-gmux-backlight.rules" \
  bash -euo pipefail "$migration"
cmp -s "$udev_src" "$migrate_etc/udev/rules.d/90-apple-gmux-backlight.rules" ||
  fail "migration writes the udev rule on gmux hardware"
[[ ! -s $calls ]] || fail "migration does not sudo when dest is not under /etc" "$(cat "$calls")"
pass "migration installs the udev rule without a privilege hop in tests"

# Second run is a no-op copy of the same bytes.
PATH="$stub_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_GMUX_UDEV_SRC="$udev_src" \
  OMARCHY_GMUX_UDEV_DEST="$migrate_etc/udev/rules.d/90-apple-gmux-backlight.rules" \
  bash -euo pipefail "$migration"
cmp -s "$udev_src" "$migrate_etc/udev/rules.d/90-apple-gmux-backlight.rules" ||
  fail "migration changes an already installed rule"
pass "migration is idempotent"
