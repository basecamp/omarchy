#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

installer="$ROOT/bin/omarchy-install-gaming-xbox-controllers"
migration="$ROOT/migrations/1787689809.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'omarchy-pkg-add %s\n' "$*" >>"$CALLS"
STUB

cat >"$stub_bin/omarchy-pkg-present" <<'STUB'
#!/bin/bash
[[ $1 == "xpadneo-dkms" && ${XPADNEO_INSTALLED:-1} == 1 ]]
STUB

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
printf 'tester input\n'
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"

case "$1" in
  rm)
    exec "$@"
    ;;
  tee)
    cat >/dev/null
    ;;
esac
STUB

chmod +x "$stub_bin/"*
export CALLS="$test_dir/calls"

: >"$CALLS"
USER=tester PATH="$stub_bin:$PATH" bash "$installer" >/dev/null

grep -qx 'omarchy-pkg-add linux-headers xpadneo-dkms' "$CALLS" ||
  fail "Xbox controller installer installs xpadneo" "$(cat "$CALLS")"
grep -qx 'sudo tee /etc/modules-load.d/xpadneo.conf' "$CALLS" ||
  fail "Xbox controller installer enables xpadneo at boot" "$(cat "$CALLS")"
grep -qx 'sudo modprobe hid_xpadneo' "$CALLS" ||
  fail "Xbox controller installer loads xpadneo now" "$(cat "$CALLS")"
pass "Xbox controller installer configures Bluetooth support"

if grep -Eq 'blacklist-xpad|modprobe -r xpad' "$CALLS"; then
  fail "Xbox controller installer keeps the USB xpad driver available" "$(cat "$CALLS")"
fi
pass "Xbox controller installer keeps the USB xpad driver available"

run_migration() {
  local blacklist="$1"

  : >"$CALLS"
  OMARCHY_XPAD_BLACKLIST="$blacklist" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

blacklist="$test_dir/blacklist-xpad.conf"
printf 'blacklist xpad\n' >"$blacklist"
run_migration "$blacklist"

[[ ! -e $blacklist ]] || fail "migration removes Omarchy's legacy xpad blacklist"
grep -qx "sudo modprobe xpad" "$CALLS" ||
  fail "migration loads the restored USB driver" "$(cat "$CALLS")"
pass "migration restores wired Xbox controller support"

run_migration "$blacklist"
[[ ! -s $CALLS ]] || fail "migration no-ops after the blacklist is gone" "$(cat "$CALLS")"
pass "migration is idempotent"

printf 'blacklist xpad\noptions xpad auto_poweroff=1\n' >"$blacklist"
run_migration "$blacklist"

[[ -f $blacklist ]] || fail "migration keeps a customized xpad configuration"
[[ ! -s $CALLS ]] || fail "migration leaves customized xpad configuration untouched" "$(cat "$CALLS")"
pass "migration keeps customized xpad configuration"

printf 'blacklist xpad\n' >"$blacklist"
: >"$CALLS"
XPADNEO_INSTALLED=0 OMARCHY_XPAD_BLACKLIST="$blacklist" PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null

[[ -f $blacklist ]] || fail "migration keeps an unrelated xpad blacklist without xpadneo"
[[ ! -s $CALLS ]] || fail "migration no-ops without xpadneo" "$(cat "$CALLS")"
pass "migration only repairs xpadneo installations"
